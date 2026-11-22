local mod = get_mod("DarktideCrosshairAlerts")
local GameplayAlerts = {}

local hot_join_finished = setmetatable({}, {__mode = "k"})
local hooked_decoders = setmetatable({}, {__mode = "k"})

mod:hook_require("scripts/extension_systems/decoder_device/decoder_device_extension", function(class)
    if type(class) ~= "table" or type(class.hot_join_sync) ~= "function" or hooked_decoders[class] then
        return
    end
    -- The client receives this flag, but hot_join_sync does not store it in _is_finished.
    mod:hook_safe(class, "hot_join_sync", function(device, _, _, _, _, finished)
        hot_join_finished[device] = finished == true or nil
    end)
    hooked_decoders[class] = true
end)

local function decoder_map(system)
    return system:unit_to_extension_map()
end

local function decoder_state(device)
    if device:is_finished() then
        return "finished"
    end
    local interrupted = device:decoding_interrupted()
    if interrupted == false then
        hot_join_finished[device] = nil
        return "running"
    end
    if hot_join_finished[device] then
        return "finished"
    end
    if interrupted == true and device:wait_for_restart() == true then
        return "needs_restart"
    end
end

function GameplayAlerts.task(state, extension_manager, enabled)
    local ok, system
    if extension_manager and extension_manager.system then
        ok, system = pcall(extension_manager.system, extension_manager, "decoder_device_system")
    end
    state.stalled = 0
    if not ok or not system or not system.unit_to_extension_map then
        return
    end
    if state.system ~= system then
        state.system = system
        state.announced = setmetatable({}, {__mode = "k"})
    end
    local available, devices = pcall(decoder_map, system)
    if not available or type(devices) ~= "table" then
        return
    end

    local alert
    state.stalled = 0
    for _, device in pairs(devices) do
        local valid, status = pcall(decoder_state, device)
        if valid and status == "needs_restart" then
            -- A waiting TASK is dropped once no device needs a restart.
            state.stalled = state.stalled + 1
        end
        if valid and status == "running" then
            state.announced[device] = nil
        elseif valid and status == "needs_restart" and not state.announced[device] then
            state.announced[device] = true
            if enabled then
                alert = "live_task"
            end
        end
    end
    return alert
end

-- Require lazily through the protected snapshot read. If the game changes these
-- interfaces, the HUD can still render previews and decoder alerts.
local Ammo, WeaponTemplate

local function ammo_snapshot(unit_data, loadout)
    Ammo = Ammo or require("scripts/utilities/ammo")
    WeaponTemplate = WeaponTemplate or require("scripts/utilities/weapon/weapon_template")
    local inventory = unit_data:read_component("inventory")
    local slot = inventory and inventory.wielded_slot
    if slot == "slot_luggable" then
        return "luggable"
    end
    local action = unit_data:read_component("weapon_action")
    if not slot or not action then
        return
    end
    if action.slot_name ~= slot or action.template_name == "none" or action.current_action_name == "action_wield"
        or action.current_action_name == "action_unwield" then
        return "switching"
    end
    local template = WeaponTemplate.current_weapon_template(action)
    if not template then
        return
    end
    if WeaponTemplate.is_melee(template) then
        return "melee"
    end
    if not WeaponTemplate.is_ranged(template)
        or not (template.hud_configuration and template.hud_configuration.uses_ammunition) then
        return
    end
    local component = unit_data:read_component(slot)
    if not component then
        return
    end
    local action_name = action.current_action_name
    local action_settings = template.actions and template.actions[action_name]
    local action_kind = action_settings and action_settings.kind
    local reloading = type(action_kind) == "string" and action_kind:find("reload", 1, true)
    if not reloading and type(action_name) == "string" then
        reloading = action_name:find("reload", 1, true)
    end
    local item = loadout and loadout.item_from_slot and loadout:item_from_slot(slot)
    return "ranged", slot, template, item, Ammo.current_ammo_in_clips(component), Ammo.max_ammo_in_clips(component),
        Ammo.current_ammo_in_reserve(component), Ammo.max_ammo_in_reserve(component), reloading
end

local function below(amount, capacity, threshold)
    return amount * 100 < capacity * threshold
end

local function crossed(previous, amount, capacity, threshold)
    return previous and amount < previous and not below(previous, capacity, threshold)
        and below(amount, capacity, threshold)
end

-- Weapons whose whole magazine is one or two rounds (double-barrelled shotguns,
-- single-shot launchers) reload after nearly every shot, so LOW MAG is noise.
-- This checks the weapon's maximum capacity, never the rounds currently left.
local small_capacity = 2
GameplayAlerts.small_capacity = small_capacity

-- A magazine is low at or below the threshold, so a five-round cylinder at 20%
-- warns on its last round rather than when empty. Small magazines also count as
-- low at min_rounds, unless that would warn after the first shot. A full
-- magazine is never low.
local function mag_is_low(amount, capacity, threshold, min_rounds)
    if amount >= capacity or capacity <= small_capacity then
        return false
    end
    if amount * 100 <= capacity * threshold then
        return true
    end
    return min_rounds > 0 and capacity - min_rounds >= 2 and amount <= min_rounds
end
GameplayAlerts.mag_is_low = mag_is_low

function GameplayAlerts.ammo(state, unit_data, mag_threshold, reserve_threshold, loadout, mag_min_rounds)
    mag_min_rounds = math.max(0, math.floor(tonumber(mag_min_rounds) or 0))
    local ok, status, slot, template, item, mag, max_mag, reserve, max_reserve, reloading =
        pcall(ammo_snapshot, unit_data, loadout)
    state.equipped, state.reloading = false, false
    if status == "melee" or status == "switching" or status == "luggable" then
        -- Keep the last ranged baseline through combat and objective-item swaps.
        state.mag_sample = "stowed: " .. status
        return
    end
    if not ok or not slot or type(mag) ~= "number" or type(max_mag) ~= "number" or max_mag <= 0
        or type(reserve) ~= "number" or type(max_reserve) ~= "number" then
        if state.mag_pending_until then
            state.mag_decision = "pending cancelled: ammo unavailable"
        end
        state.slot, state.reserve_warning, state.mag_pending_until = nil, nil, nil
        state.reserve_outcome = "unavailable or unsupported weapon"
        state.mag_sample = state.reserve_outcome
        return
    end
    state.equipped, state.reloading = true, reloading and true or false

    local same_weapon = state.slot == slot and state.template == template and state.item == item
    local same_mag = same_weapon and max_mag == state.max_mag and mag_threshold == state.mag_threshold
        and mag_min_rounds == state.mag_min_rounds
    local mag_low = mag_is_low(mag, max_mag, mag_threshold, mag_min_rounds)
    -- A first valid sample after a swap can already include a shot. Only a
    -- decrease from the same weapon's armed baseline can produce a warning.
    local mag_crossing = same_mag and state.mag and mag < state.mag
        and not mag_is_low(state.mag, max_mag, mag_threshold, mag_min_rounds) and mag_low
    local mag_alert = mag_crossing and not reloading and reserve <= state.reserve
    if (not same_mag or not mag_low) and state.mag_pending_until then
        state.mag_pending_until = nil
        state.mag_decision = not same_mag and "pending cancelled: baseline changed" or "pending cancelled: magazine recovered"
    end
    state.mag_low = mag_low
    if max_mag <= small_capacity then
        state.mag_sample = "capacity " .. max_mag .. ": LOW MAG off"
    elseif not same_mag then
        state.mag_sample = mag_low and "initial low baseline" or "new baseline"
    elseif mag_crossing and not mag_alert then
        state.mag_sample = reloading and "crossing suppressed during reload" or "crossing with reserve increase"
    elseif mag_alert then
        state.mag_sample = "threshold crossed"
    else
        state.mag_sample = mag_low and "already below threshold" or "at or above threshold"
    end
    -- LOW AMMO follows the weapon's whole supply, magazine plus reserve, the
    -- same sum vanilla Ammo.ammo_is_full uses; the clip helpers count only clips
    -- in use, so multi-clip weapons aren't double-counted. A magazine reload
    -- first returns the remaining rounds to reserve, then refills from it, so
    -- reserve alone jumps up and down around every reload while the total only
    -- falls when firing and only rises with pickups and refills.
    local total, max_total = mag + reserve, max_mag + max_reserve
    local same_supply = same_weapon and max_total == state.max_total
        and reserve_threshold == state.reserve_threshold
    -- Weapons without a reserve have nothing beyond the magazine; LOW MAG covers them.
    local has_reserve = max_reserve > 0
    local supply_low = has_reserve and below(total, max_total, reserve_threshold)
    local supply_crossing = same_supply and has_reserve
        and crossed(state.total, total, max_total, reserve_threshold)
    -- Free-transfer reload buffs empty the magazine before refilling it for
    -- free, a temporary dip that isn't spending ammunition.
    local supply_alert = supply_crossing and not reloading
    if not same_supply or not supply_low then
        state.reserve_warning = nil
    end
    if not has_reserve then
        state.reserve_outcome = "no ordinary reserve"
    elseif not same_supply then
        state.reserve_outcome = supply_low and "initial low baseline (silent)" or "baseline"
    elseif supply_crossing and not supply_alert then
        state.reserve_outcome = "crossing suppressed during reload"
    elseif supply_alert then
        state.reserve_outcome = "threshold crossed"
    elseif not supply_low and state.supply_low then
        state.reserve_outcome = "rearmed"
    end
    state.supply_low = supply_low

    state.slot, state.template, state.item = slot, template, item
    state.mag, state.max_mag, state.mag_threshold, state.mag_min_rounds = mag, max_mag, mag_threshold, mag_min_rounds
    state.reserve, state.max_reserve, state.reserve_threshold = reserve, max_reserve, reserve_threshold
    -- A reload keeps the last stable total as the baseline (H1, 0.9.2). A shot
    -- that crosses in the same sample as the reload starts is then still
    -- compared after the reload ends, while a free-transfer dip that recovers
    -- by then compares above it and stays silent. Ammunition gained during the
    -- reload (a pickup, an on-kill ammo talent) still raises it (0.9.3), so a
    -- shot that takes the refilled total back under the threshold in the
    -- sample the reload ends is a crossing, as it would be without the reload.
    if not (reloading and same_supply and state.total ~= nil) then
        state.total = total
    elseif total > state.total then
        state.total = total
    end
    state.max_total = max_total
    return mag_alert and "live_low_mag" or nil, supply_alert and "live_low_ammo" or nil
end

function GameplayAlerts.toughness(state, extension, threshold, recovery, low_enabled, break_enabled)
    state.available = extension ~= nil
    if not extension or not (low_enabled or break_enabled) then
        state.percent = nil
        state.sample = extension and "both toughness toggles off" or "toughness extension unavailable"
        return
    end
    local max_ok, maximum
    if type(extension.max_toughness) == "function" then
        max_ok, maximum = pcall(extension.max_toughness, extension)
    end
    local remaining_ok, remaining
    if type(extension.remaining_toughness) == "function" then
        remaining_ok, remaining = pcall(extension.remaining_toughness, extension)
    end
    if not max_ok or not remaining_ok or type(maximum) ~= "number" or type(remaining) ~= "number"
        or maximum <= 0 or maximum ~= maximum or remaining ~= remaining then
        state.percent = nil
        state.sample = "invalid toughness values"
        return
    end

    threshold = math.max(1, math.min(95, tonumber(threshold) or 25))
    recovery = math.max(threshold + 1, math.min(99, tonumber(recovery) or 50))
    local percent = math.min(100, 100 * math.max(0, remaining) / maximum)
    local fresh = state.extension ~= extension or state.threshold ~= threshold or state.recovery ~= recovery
    -- Compare percentages even when maximum toughness changes. The server keeps
    -- toughness damage when the maximum rises and reduces it when the maximum
    -- falls, so a capacity change alone never lowers the percentage. v0.3.0
    -- skipped every sample whose maximum differed, losing crossings.
    local comparable = not fresh and state.percent ~= nil
    local crossed_low = comparable and state.armed and state.percent >= threshold and percent < threshold
    local broke = comparable and state.percent > 0 and percent == 0
    if not fresh and state.maximum and state.maximum ~= maximum then
        state.max_changes = (state.max_changes or 0) + 1
    end

    local was_armed = state.armed
    if fresh then
        state.armed = percent >= threshold
        state.max_changes = 0
        state.sample = state.armed and "baseline (armed)" or "baseline already low (silent)"
    elseif percent > recovery then
        state.armed = true
        state.sample = was_armed and "armed" or "rearmed above recovery"
    elseif percent < threshold then
        -- An already-low baseline or a break must recover before it can warn.
        state.armed = false
        state.sample = (broke and "broke to zero") or (crossed_low and "crossed below threshold")
            or (state.percent == nil and "low after missing sample (silent)") or "below threshold, disarmed"
    else
        state.sample = state.armed and "armed" or "waiting for recovery"
    end
    state.extension, state.maximum, state.remaining, state.percent = extension, maximum, remaining, percent
    state.threshold, state.recovery = threshold, recovery

    if break_enabled and broke then
        return "live_broken"
    end
    if low_enabled and crossed_low then
        return "live_toughness"
    end
end

-- Abilities. All reads use the local PlayerUnitAbilityExtension, whose charge
-- counts come from synced unit-data components, as the vanilla ability HUD does.
local function call(extension, method, ...)
    local fn = extension[method]
    if type(fn) ~= "function" then
        error("missing " .. method, 0)
    end
    return fn(extension, ...)
end

local function read_slot(extension, ability_type)
    if not call(extension, "ability_is_equipped", ability_type) then
        return {status = "not equipped"}
    end
    -- remaining_ability_charges reports 0 while disabled, which would look like
    -- a spent charge followed by a refill, so a disabled slot keeps its baseline.
    if not call(extension, "ability_enabled", ability_type) then
        return {status = "disabled"}
    end
    local uses = call(extension, "uses_ability_charges", ability_type)
    local slot = {
        status = "ok",
        name = call(extension, "ability_name", ability_type),
        uses_charges = uses,
        charges = call(extension, "remaining_ability_charges", ability_type),
        max = uses and call(extension, "max_ability_charges", ability_type) or 0,
    }
    if type(slot.charges) ~= "number" or type(slot.max) ~= "number" then
        error("invalid charge values", 0)
    end
    if ability_type == "combat_ability" then
        -- Readiness follows the charge count; can_use_ability also flips with
        -- free-use buffs and locked-while-active states, so it's only the
        -- fallback for an ability without charges.
        if uses and slot.max > 0 then
            slot.ready = slot.charges >= 1
        else
            slot.ready = call(extension, "can_use_ability", ability_type) == true
        end
    end
    return slot
end

local function blitz_kind(name)
    if name == "adamant_whistle" then
        return "dog"
    elseif type(name) == "string" and (name:find("grenade", 1, true) or name:find("mine", 1, true)
        or name:find("friend_rock", 1, true)) then
        return "grenade"
    end
    return "blitz"
end
GameplayAlerts.blitz_kind = blitz_kind

-- Large pools such as Assail's ten knives regenerate constantly; for those only
-- "empty to available" is worth a notification.
local small_pool = 4

-- Returns the combat-ability key (or nil) and a blitz event {key, kind, gain} (or nil).
function GameplayAlerts.abilities(state, extension, ability_enabled, blitz_enabled, dog_enabled)
    state.available = extension ~= nil
    -- Whether each slot was actually read this sample. A kept baseline (missing
    -- extension, unreadable or disabled slot) is never proof of readiness.
    state.combat_fresh, state.grenade_fresh = false, false
    -- Every detected blitz charge increase this sample, notable or not, for
    -- pickup-credit accounting (0.9.4); nil when there was none.
    state.blitz_gain, state.blitz_kind = nil, nil
    if not extension then
        state.combat_status, state.blitz_status = "ability extension unavailable", "ability extension unavailable"
        return
    end
    if state.extension ~= extension then
        state.extension, state.combat, state.grenade = extension, nil, nil
    end

    local ability_alert
    local ok, combat = pcall(read_slot, extension, "combat_ability")
    if not ok then
        state.combat_status = "unreadable: " .. tostring(combat)
    elseif combat.status ~= "ok" then
        state.combat_status = combat.status .. " (baseline kept)"
    else
        local previous = state.combat
        if not previous or previous.name ~= combat.name then
            state.combat_status = combat.ready and "baseline ready (silent)" or "baseline not ready"
        elseif combat.ready and not previous.ready then
            state.combat_status = "became ready"
            if ability_enabled then
                ability_alert = "live_ability"
            end
        else
            state.combat_status = combat.ready and "ready" or "not ready"
        end
        state.combat, state.combat_fresh = combat, true
    end

    local blitz
    local valid, grenade = pcall(read_slot, extension, "grenade_ability")
    if not valid then
        state.blitz_status = "unreadable: " .. tostring(grenade)
    elseif grenade.status ~= "ok" then
        state.blitz_status = grenade.status .. " (baseline kept)"
    elseif not grenade.uses_charges or grenade.max <= 0 then
        state.blitz_status = "no charge count (e.g. Smite)"
        state.grenade, state.grenade_fresh = grenade, true
    else
        local previous = state.grenade
        local kind = blitz_kind(grenade.name)
        if not previous or previous.name ~= grenade.name or not previous.uses_charges or previous.max <= 0 then
            state.blitz_status = "baseline " .. grenade.charges .. "/" .. grenade.max .. " (silent)"
        elseif grenade.charges > previous.charges then
            local gain = grenade.charges - previous.charges
            state.blitz_gain, state.blitz_kind = gain, kind
            -- The dog command and large pools only matter when they come back from empty.
            local from_empty = previous.charges <= 0
            local notable = (kind == "dog" or grenade.max > small_pool) and from_empty
                or kind ~= "dog" and grenade.max <= small_pool
            local enabled = kind == "dog" and dog_enabled or kind ~= "dog" and blitz_enabled
            if notable and enabled then
                blitz = {key = kind == "dog" and "live_dog" or "live_blitz", kind = kind, gain = gain,
                    name = grenade.name, charges = grenade.charges}
                state.blitz_status = "gained " .. gain
            else
                state.blitz_status = "gained " .. gain .. (enabled and " (not from empty, silent)" or " (toggle off)")
            end
        else
            state.blitz_status = grenade.charges .. "/" .. grenade.max
        end
        state.grenade, state.grenade_fresh = grenade, true
    end
    return ability_alert, blitz
end

-- Grenade pickups. GrenadeInteraction and AmmunitionInteraction restore charges
-- on the server in stop(); the client runs the same stop() for its own predicted
-- interaction first, with result "success". A read-only post-hook counts those,
-- so a charge gain shortly after a pickup can stay silent.
--
-- Ordinary ammunition clips (small_clip, large_clip) carry no grenade-refill
-- flag, so they count only when the player's talents let ammunition refill the
-- blitz. Vanilla AmmunitionInteraction._can_refill_grenades checks that first:
-- the special-rule pair disable_grenade_pickups + ammo_pickups_refills_grenades
-- (Zealot Throwing Knives). Without it a clip can't restore charges, so a blitz
-- regenerating right after one still notifies (M6). Ammo crates, and any
-- ammunition pickup whose type or talents can't be read, keep counting.
local pickup_marks = setmetatable({}, {__mode = "k"})
local hooked_interactions = setmetatable({}, {__mode = "k"})
local ammo_only_pickups = {small_clip = true, large_clip = true}
GameplayAlerts.ammo_only_pickups = ammo_only_pickups
local function read_pickup_type(component)
    local target = component.target_unit
    if target ~= nil and Unit.alive(target) then
        return Unit.get_data(target, "pickup_type")
    end
end
local function pickup_type(component)
    if component == nil or type(Unit) ~= "table" then
        return
    end
    local ok, name = pcall(read_pickup_type, component)
    return ok and name or nil
end
local function mark_pickup(_, _, interactor_unit, _, _, result)
    if result == "success" and interactor_unit then
        pickup_marks[interactor_unit] = (pickup_marks[interactor_unit] or 0) + 1
    end
end
local special_rule_names
local function ammo_refills_blitz(unit)
    if not special_rule_names then
        local ok, settings = pcall(require, "scripts/settings/ability/special_rules_settings")
        local rules = ok and type(settings) == "table" and settings.special_rules or {}
        special_rule_names = {rules.disable_grenade_pickups or "disable_grenade_pickups",
            rules.ammo_pickups_refills_grenades or "ammo_pickups_refills_grenades"}
    end
    local talents = ScriptUnit.has_extension(unit, "talent_system")
    if not talents then
        error("no talent extension", 0)
    end
    return talents:has_special_rule(special_rule_names[1]) and talents:has_special_rule(special_rule_names[2]) and true
        or false
end
-- true, false, or nil when the talents can't be read.
local function talents_refill_blitz(unit)
    if type(ScriptUnit) ~= "table" then
        return
    end
    local ok, refills = pcall(ammo_refills_blitz, unit)
    if ok then
        return refills
    end
end
GameplayAlerts.talents_refill_blitz = talents_refill_blitz
local function mark_ammunition_pickup(interaction, world, interactor_unit, component, t, result)
    if not ammo_only_pickups[pickup_type(component)] or talents_refill_blitz(interactor_unit) ~= false then
        mark_pickup(interaction, world, interactor_unit, component, t, result)
    end
end
local pickup_hooks = {
    ["scripts/extension_systems/interaction/interactions/grenade_interaction"] = mark_pickup,
    ["scripts/extension_systems/interaction/interactions/ammunition_interaction"] = mark_ammunition_pickup,
}
for _, path in ipairs({"scripts/extension_systems/interaction/interactions/grenade_interaction",
    "scripts/extension_systems/interaction/interactions/ammunition_interaction"}) do
    mod:hook_require(path, function(class)
        if type(class) ~= "table" or type(class.stop) ~= "function" or hooked_interactions[class] then
            return
        end
        mod:hook_safe(class, "stop", pickup_hooks[path])
        hooked_interactions[class] = true
    end)
end
function GameplayAlerts.pickup_count(unit)
    return unit and pickup_marks[unit] or 0
end

-- Stimms. The Hive Scum stimm (syringe_broker_buff, 15 s plus the Stimm Lab
-- syringe_duration stat, applied through Buff.add_duration) and the picked-up
-- combat stimms (power, speed, ability: 15 s) all share unique_buff_id
-- "syringe_stimm", so injecting another replaces the running instance. Only
-- that running buff is read: never the injection action, the pocketable item
-- or the ability cooldown. Its remaining time is duration() * duration_progress(),
-- the values the vanilla buff bar shows, which include extensions and server
-- start-time corrections. Stimm Supply (field) variants and the corruption-heal
-- stimm don't carry that id; the field variants have no duration at all.
local stimm_family = "syringe_stimm"
-- An extension must lift the remaining time this far past the threshold to
-- rearm, so small start-time corrections near the threshold can't warn twice.
local stimm_rearm_margin = 1
GameplayAlerts.stimm_rearm_margin = stimm_rearm_margin

local function read_stimm(extension)
    local buffs = extension:buffs()
    if type(buffs) ~= "table" then
        error("no buff list", 0)
    end
    local found, remaining, name, found_duration
    for _, buff in pairs(buffs) do
        local template = type(buff) == "table" and type(buff.template) == "function" and buff:template()
        if type(template) == "table" and template.unique_buff_id == stimm_family and not buff:finished() then
            local duration, progress = buff:duration(), buff:duration_progress()
            if type(duration) == "number" and duration > 0 and duration < math.huge
                and type(progress) == "number" and progress == progress then
                local left = duration * math.max(0, math.min(1, progress))
                if not remaining or left > remaining then
                    found, remaining, name, found_duration = buff, left, template.name, duration
                end
            end
        end
    end
    return found, remaining, name, found_duration
end

-- Returns "live_stimm" once per stimm cycle when its remaining time falls to the threshold.
function GameplayAlerts.stimm(state, extension, threshold, enabled)
    threshold = math.max(1, math.min(10, tonumber(threshold) or 3))
    local ok, buff, remaining, name, duration
    if extension and type(extension.buffs) == "function" then
        ok, buff, remaining, name, duration = pcall(read_stimm, extension)
    end
    if not ok or not buff or remaining <= 0 then
        state.status = not extension and "buff extension unavailable"
            or not ok and "unreadable: " .. tostring(buff)
            or state.buff and "ended" or "no active stimm"
        state.buff, state.remaining, state.name, state.duration = nil, nil, nil, nil
        return
    end
    local alert
    if buff ~= state.buff or threshold ~= state.threshold then
        -- A new injection is a new instance. Joining or resampling inside the
        -- threshold stays silent rather than guessing when it crossed.
        state.armed = remaining > threshold
        state.status = buff ~= state.buff and (state.armed and "active, armed" or "active inside threshold (silent)")
            or "threshold changed"
    elseif state.armed and remaining <= threshold then
        state.armed = false
        state.status = "crossed threshold"
        alert = enabled and "live_stimm" or nil
    elseif not state.armed and remaining > threshold + stimm_rearm_margin then
        state.armed = true
        state.status = "extended, rearmed"
    elseif not state.armed and remaining > threshold and state.duration and duration > state.duration + 0.05 then
        -- A genuine extension (Buff.add_duration raises duration()) out of the
        -- warning window rearms at once (0.9.3). Start-time corrections move only
        -- the start time, not duration(), so they still need the 1 s margin.
        state.armed = true
        state.status = "extended out of warning window, rearmed"
    end
    state.buff, state.remaining, state.name, state.threshold = buff, remaining, name, threshold
    state.duration = duration
    return alert
end

-- One live message on screen. A new decoder interruption can replace any
-- active message, including a previous TASK from a different interruption.
-- STIM sits below TASK and toughness and above ammunition: it is only useful
-- in the few seconds before the effect ends, while ammo warnings can wait.
local priority = {live_task = 12, live_broken = 9, live_toughness = 6, live_stimm = 5.5, live_low_mag = 5,
    live_low_ammo = 4, live_ability = 3, live_dog = 2, live_blitz = 1}
GameplayAlerts.priority = priority
function GameplayAlerts.select(current, task, mag, reserve, minimum_visible, toughness, resource, stimm)
    local shown = current and priority[current] or 0
    if task then
        -- A new interruption replaces any TASK or lower alert.
        if priority.live_task >= shown then
            return task
        end
        return
    end
    if toughness then
        if not current or priority[toughness] > priority[current] then
            return toughness
        end
    end
    -- Like toughness, STIM interrupts lower alerts at once rather than waiting.
    if stimm and (not current or priority[stimm] > priority[current]) then
        return stimm
    end
    if minimum_visible then
        return
    end
    local new = mag or reserve
    if new then
        if not current or priority[new] >= priority[current] then
            return new
        end
        return
    end
    -- Ability and blitz notices never interrupt anything of equal or higher rank.
    if resource and (not current or priority[resource] > priority[current]) then
        return resource
    end
end

return GameplayAlerts
