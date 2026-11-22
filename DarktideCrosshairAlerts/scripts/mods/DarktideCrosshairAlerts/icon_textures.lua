-- Approved alert icons, loaded through the optional Simple Assets mod.
--
-- Simple Assets serves each local PNG to vanilla's Managers.url_loader, which
-- returns a texture object; the HUD draws it with the default UI material
-- ("ui_default_base") through material_values.texture_map, as Simple Assets'
-- own demo does. Without Simple Assets, or while an icon is unavailable, the
-- alert falls back to text.
--
-- Reference ownership (vanilla UrlLoaderManager): every load_texture call takes
-- one reference on its URL, even when it returns a cached result, and a texture
-- is destroyed only when its count returns to 0. A failed load is cached too:
-- later calls are rejected at once until the count reaches 0. Simple Assets has
-- no unload of its own and reports the loader's URL in each image result (its
-- own read or format errors carry no URL and hold no reference).
--
-- Each file is requested on its own, so one file that raises or never settles
-- costs only that file, and its reference is counted the moment its result
-- arrives, against the loader that issued it. Each reference is given back once:
--   * a failed URL at once, which clears vanilla's cached failure before a retry;
--   * a loaded texture only on mod unload (DMF reload or game exit), so ordinary
--     HUD recreation and mission changes keep using the same textures;
--   * a result that arrives after unload as soon as it arrives, unused.
-- If the loader can't take a reference back at unload, it is kept in a DMF
-- persistent table and returned by the next load of the mod, provided the same
-- loader is still in place (a replaced loader has destroyed its textures).
-- DMF destroys this mod's HUD element before on_unload, and texture() returns
-- nil after release, so no HUD draws a texture once it is given back.
local Icons = {}

-- Alert key -> approved artwork file name (HUD-Icon-Pack).
Icons.files = {
    live_task = "objective",
    live_low_mag = "magazine",
    live_low_ammo = "low-ammunition",
    live_toughness = "shield",
    live_broken = "broken-shield",
    live_ability = "ability-ready",
    live_blitz = "grenade",
    live_dog = "dog-command",
    live_stimm = "stimulant",
}
-- Two exports: 64 px for ordinary resolutions, 128 px when the icon is drawn
-- larger than 64 screen pixels (for example at 4K), so it is never magnified.
Icons.sizes = {64, 128}
-- An explicit mods/ path doesn't depend on Simple Assets inferring the caller.
Icons.root = "mods/DarktideCrosshairAlerts/assets/icons"
-- Each file is tried at most this many times; the delays (seconds of HUD time)
-- come before the second and third attempts. A file still failing after that
-- stays as text until the mod is reloaded.
Icons.max_attempts = 3
Icons.retry_delays = {5, 30}

local state = {
    status = "idle", -- idle, unavailable, loading, ready, failed or released
    textures = {[64] = {}, [128] = {}},
    missing = {}, -- files without a texture after their latest attempt
    attempts = {}, -- path -> attempts started
    pending = {}, -- path -> token of the request in flight
    failed = {}, -- path -> true while its latest attempt failed
    owned = {}, -- loader -> {URL -> references held by this module}
    requests = 0,
    loaded = 0,
}
Icons.state = state

-- References a previous load of the mod could not give back, by loader. Kept by
-- DMF across reloads; a plain table where DMF's persistent tables are missing.
local mod = type(get_mod) == "function" and get_mod("DarktideCrosshairAlerts") or nil
local owed = mod and type(mod.persistent_table) == "function" and mod:persistent_table("icon_references_owed") or {}
Icons.owed = owed

function Icons.path(size, key)
    return ("%s/%d/%s.png"):format(Icons.root, size, Icons.files[key])
end

local lookup = {}
for _, size in ipairs(Icons.sizes) do
    for key in pairs(Icons.files) do
        lookup[Icons.path(size, key)] = {size = size, key = key}
    end
end

local function current_loader()
    local loader = Managers and Managers.url_loader
    if type(loader) == "table" and type(loader.unload_texture) == "function" then
        return loader
    end
end

-- Hands every reference in held ({URL -> count}) back to loader. vanilla raises
-- on an unheld URL; these were all counted on this loader, so an error here
-- must not escape into DMF's unload.
local function hand_back(loader, held)
    for url, count in pairs(held) do
        for _ = 1, count do
            pcall(loader.unload_texture, loader, url)
        end
    end
end

-- Settles references owed by earlier loads of the mod: returned to the loader
-- that issued them, dropped if that loader has been replaced, kept while no
-- loader is available.
local function settle_owed()
    local loader = current_loader()
    if not loader then
        return
    end
    for owner, held in pairs(owed) do
        owed[owner] = nil
        if owner == loader then
            hand_back(loader, held)
        end
    end
end

local function count(owner, url, delta)
    local held = state.owned[owner] or {}
    state.owned[owner] = held
    local total = (held[url] or 0) + delta
    held[url] = total > 0 and total or nil
    if next(held) == nil then
        state.owned[owner] = nil
    end
end

-- Gives back one reference this module counted for url on owner.
local function give_back(owner, url)
    local held = state.owned[owner]
    if not (url and held and held[url]) then
        return
    end
    count(owner, url, -1)
    if owner == current_loader() then
        pcall(owner.unload_texture, owner, url)
    elseif current_loader() == nil then
        -- Briefly no loader: the next load of the mod gives it back.
        local debts = owed[owner] or {}
        owed[owner] = debts
        debts[url] = (debts[url] or 0) + 1
    end -- A replaced loader has already destroyed its textures.
end

local function refresh_status(reason)
    state.loaded = 0
    for _, size in ipairs(Icons.sizes) do
        for _ in pairs(state.textures[size]) do
            state.loaded = state.loaded + 1
        end
    end
    local missing = {}
    for path in pairs(state.failed) do
        missing[#missing + 1] = path
    end
    table.sort(missing)
    state.missing = missing
    if reason then
        state.reason = tostring(reason)
    end
    if next(state.pending) ~= nil then
        state.status = "loading"
    elseif state.loaded > 0 then
        state.status, state.reason = "ready", nil
    else
        state.status = "failed"
        state.reason = state.reason or "no icon texture loaded"
    end
end

-- Records the outcome of one file. An image result's URL holds a reference taken
-- by load_texture, so it is counted first, then kept or given back.
local function settle(path, token, result, reason)
    local url = type(result) == "table" and type(result.url) == "string" and result.url or nil
    local owner = url and current_loader()
    if owner then
        count(owner, url, 1)
    end
    if state.status == "released" or state.pending[path] ~= token then
        give_back(owner, url) -- After unload, or a second outcome for one request: unused.
        return
    end
    state.pending[path] = nil
    local entry = lookup[path]
    local ok = type(result) == "table" and result.is_ok and result.texture ~= nil
    if ok and not state.textures[entry.size][entry.key] then
        state.textures[entry.size][entry.key] = result.texture
        state.failed[path] = nil
    else
        give_back(owner, url) -- A failure, or a duplicate of a texture already held.
        if not ok then
            state.failed[path] = true
            reason = reason or type(result) == "table" and (result.error or result.url) or nil
            local attempts = state.attempts[path]
            if attempts < Icons.max_attempts then
                local retry = state.retry or {paths = {}, delay = Icons.retry_delays[attempts] or 30}
                retry.paths[#retry.paths + 1] = path
                state.retry = retry
            end
        end
    end
    refresh_status(reason or (not ok and "no icon texture loaded" or nil))
end

-- Requests each file through Simple Assets on its own.
local function load(simple_assets, paths)
    state.requests = state.requests + 1
    for _, path in ipairs(paths) do
        state.attempts[path] = (state.attempts[path] or 0) + 1
        local token = {}
        state.pending[path] = token
    end
    state.status = "loading"
    for _, path in ipairs(paths) do
        local token = state.pending[path]
        local ok, promise
        if type(simple_assets) == "table" and type(simple_assets.load_textures) == "function" then
            ok, promise = pcall(simple_assets.load_textures, {path})
        else
            ok, promise = true, "Simple Assets is not available"
        end
        if not ok or type(promise) ~= "table" or type(promise.next) ~= "function" then
            settle(path, token, nil, ok and (type(promise) == "string" and promise or "load_textures returned no promise")
                or promise)
        else
            -- Item failures resolve the promise with a failure entry; a rejection
            -- or an error in the callback still settles the file.
            local chained = promise:next(function(results)
                settle(path, token, type(results) == "table" and results[path] or nil)
            end)
            if type(chained) == "table" and type(chained.catch) == "function" then
                chained:catch(function(load_error)
                    settle(path, token, nil,
                        type(load_error) == "table" and (load_error.error or load_error.url) or load_error)
                end)
            end
        end
    end
    if state.status ~= "released" then
        refresh_status()
    end
    return state.status
end

-- Starts the one-time load. Safe to call repeatedly: loading, ready, failed
-- and released states return at once, so textures are never requested twice.
function Icons.request(simple_assets)
    -- "unavailable" may retry: Simple Assets might not have been ready yet.
    if state.status ~= "idle" and state.status ~= "unavailable" then
        return state.status
    end
    if type(simple_assets) ~= "table" or type(simple_assets.load_textures) ~= "function" then
        state.status, state.reason = "unavailable", "Simple Assets is not installed or failed to initialise"
        return state.status
    end
    settle_owed()
    local paths = {}
    for path in pairs(lookup) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    return load(simple_assets, paths)
end

-- True when a scheduled retry is due at HUD time t. The first call after a
-- failure starts the delay, so retries follow the clock that asks; a clock that
-- went backwards (a new HUD or mission) counts as due. Only a field check when
-- nothing is waiting. A file still in flight doesn't hold up another's retry.
function Icons.retry_due(t)
    local retry = state.retry
    if not retry or state.status == "released" or type(t) ~= "number" then
        return false
    end
    if not retry.at then
        retry.from, retry.at = t, t + retry.delay
        return false
    end
    return t >= retry.at or t < retry.from
end

-- Retries only the files that failed and still have attempts left; textures
-- already loaded are kept.
function Icons.retry(simple_assets)
    local retry = state.retry
    if not retry or state.status == "released" then
        return state.status
    end
    state.retry = nil
    return load(simple_assets, retry.paths)
end

-- Gives back every reference this module holds and stops further use. Called
-- from the mod's on_unload, after DMF has destroyed the HUD element. Results
-- still in flight are given back when they arrive.
function Icons.release()
    state.status, state.retry = "released", nil
    state.textures = {[64] = {}, [128] = {}}
    state.loaded = 0
    settle_owed()
    for owner, held in pairs(state.owned) do
        for url, n in pairs(held) do
            for _ = 1, n do
                give_back(owner, url)
            end
        end
    end
end

-- The cached texture for an alert, preferring the export closest to the drawn
-- size; nil without Simple Assets, while unavailable, or after release.
function Icons.texture(key, pixel_size)
    if state.status == "released" or not Icons.files[key] then
        return
    end
    local large = (pixel_size or 0) > 64
    local textures = state.textures
    return (large and textures[128][key] or textures[64][key]) or textures[128][key]
end

return Icons
