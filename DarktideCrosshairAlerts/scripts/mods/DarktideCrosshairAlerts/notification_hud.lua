local mod = get_mod("DarktideCrosshairAlerts")
local UIWidget = require("scripts/managers/ui/ui_widget")
local workspace = require("scripts/settings/ui/ui_workspace_settings")
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")
local AlertHud = class("HudElementDarktideCrosshairAlerts", "HudElementBase")

local pop_time, fade_out = 0.18, 0.18
local default_color = {255, 255, 245, 107}
local ammo_validity, ammo_minimum_visible = 10, 1
-- Ability and blitz notices wait at most this long behind a higher alert, in a
-- single slot, and are dropped if the resource is no longer available.
local resource_validity = 4
local resource_keys = {live_ability = true, live_dog = true, live_blitz = true}
-- Toughness warnings show for a fixed 2.5 s.
local urgent_keys = {live_toughness = true, live_broken = true}
-- STIM shows for at most this long, and never past the effect's end.
local stimm_display = 2
-- A blitz gain this soon after the player's own grenade or ammo pickup is the pickup.
local pickup_window = 2

-- Four offset text passes give the outline the same glyphs and scale as the label.
local outline_offsets = {{-2, 0, 0}, {2, 0, 0}, {0, -2, 0}, {0, 2, 0}}
local outline_color = {255, 8, 6, 3}
-- Icon only mode hides the text, but only when an icon is actually drawn.
local function text_visible(content)
    return content.show_text ~= false
end
local text_passes = {}
for i, offset in ipairs(outline_offsets) do
    text_passes[i] = {
        pass_type = "text",
        value_id = "message",
        style_id = "outline_" .. i,
        visibility_function = text_visible,
        style = {
            font_type = "proxima_nova_bold",
            font_size = 23,
            drop_shadow = false,
            text_horizontal_alignment = "center",
            text_vertical_alignment = "center",
            text_color = {outline_color[1], outline_color[2], outline_color[3], outline_color[4]},
            offset = {offset[1], offset[2], offset[3]},
        },
    }
end
text_passes[#text_passes + 1] = {
    pass_type = "text",
    value = "",
    value_id = "message",
    style_id = "label",
    visibility_function = text_visible,
    style = {
        font_type = "proxima_nova_bold",
        font_size = 23,
        drop_shadow = true,
        text_horizontal_alignment = "center",
        text_vertical_alignment = "center",
        text_color = {default_color[1], default_color[2], default_color[3], default_color[4]},
        offset = {0, 0, 1},
    },
}

-- Category colours (alpha is replaced by the fade). TASK and previews keep the
-- player's own Notification colour; "Colour alerts by category" off uses it for all.
local palette = {
    live_low_mag = {255, 255, 200, 61}, -- amber yellow
    live_low_ammo = {255, 255, 77, 77}, -- red
    live_broken = {255, 255, 77, 77}, -- red
    live_toughness = {255, 77, 210, 255}, -- cyan
    live_ability = {255, 255, 214, 40}, -- warm golden yellow
    live_dog = {255, 200, 168, 255}, -- lavender
    live_blitz = {255, 215, 215, 215}, -- light grey
    live_stimm = {255, 170, 255, 80}, -- lime
}

-- Approved icon artwork (icon_textures.lua), drawn like Simple Assets' demo and
-- vanilla's emote wheel: the default UI material with the loaded texture as its
-- texture_map, tinted by the pass colour. Four dark copies offset by 1.5 units
-- outline it the way the text is outlined. The passes follow the text in the
-- same widget, so they share its anchor, pop, fade and colour,
-- and are only visible while a loaded texture is assigned.
local icon_material = "content/ui/materials/base/ui_default_base"
local icon_size = 28 -- UI units at the default alert size (23); scales with the text.
local icon_outline_offsets = {{-1.5, 0}, {1.5, 0}, {0, -1.5}, {0, 1.5}}
local function icon_visible(content)
    return content.icon_texture ~= nil
end
local icon_style_ids = {}
for i = 1, #icon_outline_offsets + 1 do
    local style_id = i <= #icon_outline_offsets and "icon_outline_" .. i or "icon"
    icon_style_ids[i] = style_id
    text_passes[#text_passes + 1] = {
        pass_type = "texture",
        value = icon_material,
        style_id = style_id,
        visibility_function = icon_visible,
        style = {
            horizontal_alignment = "center",
            vertical_alignment = "center",
            size = {icon_size, icon_size},
            offset = {0, 0, style_id == "icon" and 2 or 1},
            color = {255, 255, 255, 255},
            material_values = {texture_map = nil, use_placeholder_texture = 0},
        },
    }
end
local text_base_offsets = {label = 0}
for i, offset in ipairs(outline_offsets) do
    text_base_offsets["outline_" .. i] = offset[1]
end
local display_modes = {text = true, icon = true, icon_text = true}
local function display_mode()
    local mode = mod:get("alert_display")
    return display_modes[mode] and mode or "icon_text"
end

-- Vanilla's text measurement where available; otherwise a bold-font estimate.
local UIRenderer
local function text_width(ui_renderer, text, font_size)
    if ui_renderer then
        if UIRenderer == nil then
            local ok, module = pcall(require, "scripts/managers/ui/ui_renderer")
            UIRenderer = ok and type(module) == "table" and module or false
        end
        if UIRenderer and type(UIRenderer.text_size) == "function" then
            local ok, width = pcall(UIRenderer.text_size, ui_renderer, text, "proxima_nova_bold", font_size)
            if ok and type(width) == "number" and width > 0 then
                return width
            end
        end
    end
    return #text * font_size * 0.6
end

-- Places the icon beside the text (or alone) at the current pop scale. Text
-- only, no Simple Assets, still loading or a missing file: text as before.
local function layout(widget, key, message, font_size, opacity, color, ui_renderer)
    local mode = display_mode()
    local content, style = widget.content, widget.style
    local scale = font_size / 23
    local size = icon_size * scale
    local texture
    if mode ~= "text" and key and mod.icons then
        local render_scale = ui_renderer and tonumber(ui_renderer.scale) or 1
        texture = mod.icons.texture(key, size * render_scale)
    end
    content.icon_texture = texture
    content.show_text = texture == nil or mode ~= "icon"
    local text_x, icon_x = 0, 0
    if texture and content.show_text then
        local gap = 8 * scale
        local width = text_width(ui_renderer, message, font_size)
        local total = size + gap + width
        icon_x = -total / 2 + size / 2
        text_x = total / 2 - width / 2
    end
    local alpha = math.floor(opacity * 255 + 0.5)
    for i, style_id in ipairs(icon_style_ids) do
        local icon_style = style[style_id]
        local shift = icon_outline_offsets[i]
        local rgb = shift and outline_color or color
        icon_style.size[1], icon_style.size[2] = size, size
        icon_style.offset[1] = icon_x + (shift and shift[1] or 0)
        icon_style.offset[2] = shift and shift[2] or 0
        icon_style.color[1], icon_style.color[2], icon_style.color[3], icon_style.color[4] =
            alpha, rgb[2], rgb[3], rgb[4]
        icon_style.material_values.texture_map = texture
    end
    for style_id, base_x in pairs(text_base_offsets) do
        style[style_id].offset[1] = base_x + text_x
    end
end

local definitions = {
    scenegraph_definition = {
        screen = workspace.screen,
        alert = {
            parent = "screen",
            horizontal_alignment = "center",
            vertical_alignment = "center",
            size = {260, 44},
            position = {0, 60, 5},
        },
    },
    widget_definitions = {
        alert = UIWidget.create_definition(text_passes, "alert"),
    },
}

function AlertHud:init(parent, draw_layer, start_scale)
    AlertHud.super.init(self, parent, draw_layer, start_scale, definitions)
    -- Idempotent: icons already loading, loaded or failed are not requested again.
    if mod.request_icons then
        mod.request_icons()
    end
    self._decoder_state = {}
    self:reset_live_alerts()
end

function AlertHud:preview_unit()
    local parent = self._parent
    local unit = parent and parent.player_unit and parent:player_unit()
    local extensions = unit and parent.player_extensions and parent:player_extensions()
    local data = extensions and extensions.unit == unit and extensions.unit_data
    if not data or not data.read_component then
        return
    end
    local ok, state, disabled = pcall(function()
        return data:read_component("character_state"), data:read_component("disabled_character_state")
    end)
    if ok and state and state.state_name and disabled and not disabled.is_disabled
        and not PlayerUnitStatus.is_disabled(state) then
        return unit, data, extensions.visual_loadout, extensions.toughness, extensions.ability, extensions.buff
    end
end

function AlertHud:show_preview(persistent)
    self._preview = {
        unit = self:preview_unit(),
        message = mod:localize(persistent and "preview_hold" or "preview_brief"),
        persistent = persistent,
    }
end

function AlertHud:clear_preview()
    self._preview = nil
end

function AlertHud:dismiss_preview()
    local preview = self._preview
    if preview then
        preview.dismissed = true
    end
end

function AlertHud:reset_live_alerts()
    self._live = nil
    self._ammo_state = {}
    self._toughness_state = {}
    self._ability_state = {}
    self._stimm_state = {}
    self._stimm_pending = nil
    self._task_pending = nil
    self._pickup_count, self._pickup_credits = nil, nil
    self._resource_queue = nil
    self._next_sample, self._last_sample = nil, nil
    self._tracked_unit = nil
end

-- Toughness keys share their IDs with the Mod Options toggles, so their
-- on-screen labels live under separate localization keys.
local function alert_label(key)
    if key == "live_broken" then
        return mod:localize("alert_broken")
    elseif key == "live_toughness" then
        return mod:localize("alert_toughness")
    elseif key == "live_ability" then
        return mod:localize("alert_ability")
    elseif key == "live_dog" then
        return mod:localize("alert_dog")
    elseif key == "live_blitz" then
        return mod:localize("alert_blitz", 1)
    elseif key == "live_low_mag" then
        return mod:localize("alert_mag")
    elseif key == "live_low_ammo" then
        return mod:localize("alert_ammo")
    elseif key == "live_stimm" then
        return mod:localize("alert_stimm_short")
    end
    return mod:localize(key)
end

local function resource_message(event)
    if event.key == "live_blitz" then
        return mod:localize(event.kind == "grenade" and "alert_grenade" or "alert_blitz", event.gain or 1)
    end
    return mod:localize(event.key == "live_dog" and "alert_dog" or "alert_ability")
end

local function pause_reserve(ammo, live, t, outcome)
    local warning = ammo.reserve_warning
    if live.reserve_warning == warning and warning and t < warning.valid_until then
        warning.elapsed = warning.elapsed + t - live.resumed_at
        warning.pending = warning.elapsed < warning.duration
    end
    if warning and live.reserve_warning == warning then
        ammo.reserve_outcome = outcome
    end
end

-- A STIM crossing waits in one slot only while that same stimm is still
-- running and still inside the threshold; the shown text is its remaining time
-- when it actually appears. An extension that rearms the warning (M2, 0.9.2)
-- drops a waiting STIM: only a new crossing warns again. A STIM already on
-- screen finishes its short display as before.
function AlertHud:stimm_candidate(gameplay, buff_extension)
    local state = self._stimm_state
    local enabled = mod:get("live_stimm")
    if gameplay.stimm(state, buff_extension, mod:get("stimm_threshold"), enabled) then
        self._stimm_pending = {buff = state.buff}
    end
    local pending = self._stimm_pending
    if pending and (not enabled or pending.buff ~= state.buff or not state.remaining or state.remaining <= 0
        or state.armed) then
        self._stimm_pending = nil
    end
    local live = self._live
    -- The effect ended or was replaced: an on-screen STIM goes at once.
    if live and live.key == "live_stimm" and (not enabled or live.buff ~= state.buff) then
        self._live = nil
    end
    return self._stimm_pending and "live_stimm"
end

function AlertHud:sample_live(unit_data, t, loadout, toughness_extension, ability_extension, buff_extension)
    local gameplay = mod.gameplay_alerts
    if not gameplay or (self._next_sample and t < self._next_sample) then
        return
    end
    self._next_sample = t + 0.10

    local manager = Managers and Managers.state and Managers.state.extension
    -- TASK is offered from a single slot while a device still needs a restart.
    local decoder = self._decoder_state
    if gameplay.task(decoder, manager, mod:get("live_task")) then
        self._task_pending = {}
    end
    local task_pending = self._task_pending
    if task_pending and (not mod:get("live_task") or (decoder.stalled or 0) == 0) then
        task_pending, self._task_pending = nil, nil
    end
    local task = task_pending and "live_task"
    local toughness_state = self._toughness_state
    local toughness = gameplay.toughness(toughness_state, toughness_extension,
        mod:get("toughness_threshold"), mod:get("toughness_recovery"),
        mod:get("live_toughness"), mod:get("live_broken"))
    if toughness then
        toughness_state.decided_at = t
    end
    local ammo = self._ammo_state
    local mag_enabled, reserve_enabled = mod:get("live_low_mag"), mod:get("live_low_ammo")
    local mag, reserve
    if mag_enabled or reserve_enabled or mod:get("reserve_diagnostics") or mod:get("mag_diagnostics") then
        mag, reserve = gameplay.ammo(ammo, unit_data,
            mod:get("mag_threshold"), mod:get("reserve_threshold"), loadout, mod:get("mag_min_rounds"))
    else
        ammo.slot, ammo.equipped = nil, false
    end

    if not reserve_enabled then
        ammo.reserve_warning = nil
        ammo.reserve_outcome = "toggle disabled"
    elseif reserve then
        ammo.reserve_warning = {valid_until = t + ammo_validity, pending = true, elapsed = 0}
        ammo.reserve_outcome = "deferred by higher priority"
    end
    local warning = ammo.reserve_warning
    local previous_sample = self._last_sample or t
    self._last_sample = t
    if warning and warning.pending and not ammo.equipped then
        -- A waiting LOW AMMO can't show while the ranged weapon is stowed, so its
        -- ten seconds only count while it is out; it shows when the player draws
        -- it again, unless a pickup has lifted the supply or the weapon changed.
        warning.valid_until = warning.valid_until + (t - previous_sample)
        ammo.reserve_outcome = "waiting for ranged weapon"
    end
    if warning and warning.pending and t >= warning.valid_until then
        warning.pending = false
        ammo.reserve_outcome = "expired while deferred"
    end

    if not mag_enabled then
        ammo.mag_pending_until = nil
        ammo.mag_decision = "toggle disabled"
    elseif mag then
        ammo.mag_pending_until = t + ammo_validity
        ammo.mag_decision = "queued by threshold crossing"
    elseif ammo.mag_pending_until and t >= ammo.mag_pending_until then
        ammo.mag_pending_until = nil
        ammo.mag_decision = "expired while deferred"
    end

    local live = self._live
    if live and (live.key == "live_low_mag" or live.key == "live_low_ammo") and (not ammo.equipped
        or live.slot ~= ammo.slot or live.template ~= ammo.template or live.item ~= ammo.item) then
        if live.key == "live_low_ammo" then
            pause_reserve(ammo, live, t, "hidden while ranged weapon is stowed")
        end
        self._live, live = nil, nil
    end

    local stimm = self:stimm_candidate(gameplay, buff_extension)
    live = self._live
    local current = live and live.key
    -- Only ammo and toughness alerts get the one-second protection from ammo.
    local protected = live and not resource_keys[current] and current ~= "live_task"
        and t - live.started_at < ammo_minimum_visible
    local resource = self:resource_candidate(gameplay, ability_extension, t)
    -- A waiting RELOAD is held while the player is already reloading (M3, 0.9.2).
    -- It keeps its expiry; a reload that refills the magazine cancels it, and an
    -- interrupted one leaves it to show if it is still valid.
    local mag_held = ammo.mag_pending_until and ammo.reloading
    if mag_held then
        ammo.mag_decision = "held during reload"
    end
    local key = gameplay.select(current, task,
        ammo.equipped and ammo.mag_pending_until and not mag_held and "live_low_mag",
        ammo.equipped and warning and warning.pending and "live_low_ammo", protected, toughness, resource, stimm)
    local message = key and alert_label(key)
    if toughness then
        local blocker = task or (key ~= toughness and key) or current
        toughness_state.decision = key == toughness and "emitted " .. alert_label(toughness)
            or "dropped " .. alert_label(toughness) .. ": " .. (blocker and alert_label(blocker) or "higher priority") .. " visible"
    end
    self:record_toughness_sample(t)
    self:record_supply_sample(t)
    if not key then
        if mag and ammo.mag_pending_until then
            ammo.mag_decision = "deferred by current alert"
        end
        self:record_mag_sample(t)
        return
    end
    if current == "live_low_ammo" then
        pause_reserve(ammo, live, t, "preempted by " .. message)
    end

    local next_alert = {key = key, message = message, slot = ammo.slot,
        template = ammo.template, item = ammo.item}
    local pending = resource_keys[key] and self:take_resource(key)
    if pending then
        message = resource_message(pending)
        next_alert.message, next_alert.kind, next_alert.gain = message, pending.kind, pending.gain
        self:record_ability_decision(t, "shown " .. message)
    end
    if key == "live_task" then
        self._task_pending = nil
    elseif key == "live_stimm" then
        local stimm_state = self._stimm_state
        local remaining = stimm_state.remaining
        next_alert.message = mod:localize("alert_stimm", math.max(1, math.ceil(remaining - 0.05)))
        next_alert.buff = stimm_state.buff
        next_alert.started_at = t
        next_alert.expires_at = t + math.min(stimm_display, remaining)
        self._stimm_pending = nil
    end
    if key == "live_low_ammo" then
        warning.pending = false
        warning.duration = warning.duration or mod:get("live_low_ammo_duration")
        next_alert.reserve_warning = warning
        next_alert.resumed_at = t
        next_alert.started_at = t - warning.elapsed
        next_alert.expires_at = t + warning.duration - warning.elapsed
        ammo.reserve_outcome = warning.elapsed > 0 and "resumed" or "emitted"
    elseif key == "live_low_mag" then
        ammo.mag_pending_until = nil
        ammo.mag_decision = "emitted"
        ammo.mag_last_alert = t
    end
    if key ~= "live_low_mag" and mag and ammo.mag_pending_until then
        ammo.mag_decision = "deferred by " .. message
    end
    self._live = next_alert
    self:record_mag_sample(t)
end

-- Bounded, opt-in history of ammunition supply changes for /dca_reserve.
function AlertHud:record_supply_sample(t)
    if not mod:get("reserve_diagnostics") then
        self._supply_history = nil
        return
    end
    local ammo = self._ammo_state
    local summary = string.format("%s %s/%s %s", ammo.slot or "-", tostring(ammo.total or "-"),
        tostring(ammo.max_total or "-"), ammo.reserve_outcome or "no data")
    local history = self._supply_history or {}
    self._supply_history = history
    if history[#history] and history[#history].summary == summary then
        return
    end
    if #history == 5 then
        table.remove(history, 1)
    end
    history[#history + 1] = {at = t, summary = summary}
end

function AlertHud:record_mag_sample(t)
    if not mod:get("mag_diagnostics") then
        self._mag_history = nil
        return
    end
    local ammo = self._ammo_state
    local summary = string.format("%s %s/%s %s%s", ammo.slot or "-",
        tostring(ammo.mag or "-"), tostring(ammo.max_mag or "-"), ammo.mag_sample or "no data",
        ammo.mag_pending_until and " (pending)" or "")
    local history = self._mag_history or {}
    self._mag_history = history
    if history[#history] and history[#history].summary == summary then
        return
    end
    if #history == 5 then
        table.remove(history, 1)
    end
    history[#history + 1] = {at = t, summary = summary}
end

-- Bounded history: only state changes are kept, at most five, and only while
-- the opt-in diagnostic is enabled. Nothing is printed until /dca_toughness.
function AlertHud:record_toughness_sample(t)
    if not mod:get("toughness_diagnostics") then
        self._toughness_history = nil
        return
    end
    local state = self._toughness_state
    local summary = string.format("%s %s", state.percent and string.format("%.0f%%", state.percent) or "-",
        state.sample or "no data")
    local history = self._toughness_history or {}
    self._toughness_history = history
    if history[#history] and history[#history].sample == state.sample then
        return
    end
    if #history == 5 then
        table.remove(history, 1)
    end
    history[#history + 1] = {at = t, sample = state.sample, summary = summary}
end

-- Collects this sample's ability and blitz events into the single pending slot
-- and returns the key that may be shown. Visible blitz notices absorb further
-- gains of the same kind ("GRENADE +2") instead of queueing another notice.
-- Waiting ability and blitz notices (0.9.4). One bounded queue, at most one
-- notice per alert key, with these invariants:
--   * A notice is dropped only by its own validation (expiry, toggle, identity,
--     spent charge) or by a validated notice of higher priority.
--   * A notice whose slot can't be read this sample is "held": it keeps its own
--     deadline but neither evicts, nor is evicted by, any other notice, and it
--     can't be shown. Once readable and valid it competes again.
--   * A new event for a key already waiting merges into that notice (gain,
--     charges and deadline), so a returning notice never overwrites newer data.
--   * Among validated notices only the highest priority survives (the original
--     single-slot rule); it is the candidate returned for arbitration.
-- Visible blitz notices still absorb further gains of the same kind.
function AlertHud:resource_candidate(gameplay, extension, t)
    local state = self._ability_state
    local ability_alert, blitz = gameplay.abilities(state, extension,
        mod:get("live_ability"), mod:get("live_blitz"), mod:get("live_dog"))
    blitz = self:account_pickups(gameplay, state, blitz, t)
    local priority = gameplay.priority
    local live = self._live
    local queue = {}
    for _, notice in ipairs(self._resource_queue or {}) do
        local kept, held = self:check_resource(notice, t)
        if kept then
            kept.held = held or nil
            queue[#queue + 1] = kept
        end
    end
    local function drop_lower(winner)
        for i = #queue, 1, -1 do
            local notice = queue[i]
            if notice ~= winner and not notice.held and priority[notice.key] < priority[winner.key] then
                self:record_ability_decision(t, "dropped " .. resource_message(notice) .. " for " .. resource_message(winner))
                table.remove(queue, i)
            end
        end
    end
    local function offer(event)
        if live and event.key == "live_blitz" and live.key == "live_blitz" and live.kind == event.kind then
            live.gain = (live.gain or 1) + event.gain
            live.message = resource_message(live)
            self:record_ability_decision(t, "merged into visible " .. live.message)
            return
        end
        for i, notice in ipairs(queue) do
            if notice.key == event.key then
                if notice.kind == event.kind then
                    notice.gain = (notice.gain or 0) + (event.gain or 0)
                    notice.charges = event.charges
                    notice.until_t = t + resource_validity
                    return
                end
                self:record_ability_decision(t, "dropped " .. resource_message(notice) .. " for " .. resource_message(event))
                table.remove(queue, i)
                break
            end
        end
        for _, notice in ipairs(queue) do
            if not notice.held and priority[notice.key] > priority[event.key] then
                self:record_ability_decision(t, "dropped " .. resource_message(event) .. ": " .. resource_message(notice) .. " waiting")
                return
            end
        end
        local notice = {key = event.key, kind = event.kind, gain = event.gain, name = event.name,
            charges = event.charges, extension = state.extension, until_t = t + resource_validity}
        queue[#queue + 1] = notice
        self:record_ability_decision(t, "queued " .. resource_message(notice))
        drop_lower(notice)
    end
    if ability_alert then
        -- Bound to the equipped ability's identity (0.9.3).
        offer({key = ability_alert, name = state.combat.name})
    end
    if blitz then
        offer(blitz)
    end
    -- A notice that became readable again competes like any waiting notice.
    local best
    for _, notice in ipairs(queue) do
        if not notice.held and (not best or priority[notice.key] > priority[best.key]) then
            best = notice
        end
    end
    if best then
        drop_lower(best)
    end
    self._resource_queue = queue
    return best and best.key
end

-- Removes and returns the validated notice that arbitration chose to show.
function AlertHud:take_resource(key)
    local queue = self._resource_queue or {}
    for i, notice in ipairs(queue) do
        if notice.key == key and not notice.held then
            table.remove(queue, i)
            return notice
        end
    end
end

-- Pickup credits (0.9.4). Each counted pickup adds one credit stamped with its
-- own time; credits expire independently after the window, oldest first, and
-- a new pickup never refreshes an older one. Any detected blitz charge increase
-- (not the dog command) consumes the oldest live credit, whether or not that
-- gain would have produced a notice, so a refill that earns no notice can't
-- leave a credit behind to silence a later regeneration.
local max_pickup_credits = 8
function AlertHud:account_pickups(gameplay, state, blitz, t)
    local credits = self._pickup_credits or {}
    self._pickup_credits = credits
    local pickups = gameplay.pickup_count and gameplay.pickup_count(self._tracked_unit) or 0
    if self._pickup_count and pickups > self._pickup_count then
        for _ = 1, math.min(pickups - self._pickup_count, max_pickup_credits) do
            credits[#credits + 1] = t
        end
    end
    self._pickup_count = pickups
    while #credits > max_pickup_credits or (credits[1] and t - credits[1] > pickup_window) do
        table.remove(credits, 1)
    end
    local gain = state.blitz_gain
    if gain and state.blitz_kind ~= "dog" and credits[1] then
        table.remove(credits, 1)
        if blitz and blitz.key == "live_blitz" then
            self:record_ability_decision(t, "silent " .. resource_message(blitz) .. ": pickup")
            return nil
        end
        self:record_ability_decision(t, "pickup credit used: +" .. gain .. " without a notice")
    end
    return blitz
end

-- Validates the waiting notice against this sample's state. Returns the notice
-- (nil once dropped) and whether it is held because its slot wasn't read.
function AlertHud:check_resource(pending, t)
    if not pending then
        return
    end
    local state = self._ability_state
    local reason, held
    if t >= pending.until_t then
        reason = "expired behind higher alerts"
    elseif not mod:get(pending.key) then
        reason = "toggle off"
    elseif state.extension ~= pending.extension then
        reason = "ability extension replaced"
    elseif pending.key == "live_ability" then
        if not state.combat_fresh then
            held = true
        elseif state.combat.name ~= pending.name then
            -- Another ability being ready is not this notice's ability.
            reason = "ability changed"
        elseif not state.combat.ready then
            reason = "ability no longer ready"
        end
    elseif not state.grenade_fresh then
        held = true
    else
        local grenade = state.grenade
        if grenade.name ~= pending.name or not grenade.uses_charges or grenade.max <= 0 then
            reason = "blitz changed"
        elseif pending.key == "live_dog" then
            if grenade.charges <= 0 then
                reason = "dog command used"
            end
        elseif grenade.charges < pending.charges then
            -- Charges spent while waiting cancel that much of the gain.
            local spent = pending.charges - grenade.charges
            if spent >= pending.gain then
                reason = "charge spent"
            else
                pending.gain, pending.charges = pending.gain - spent, grenade.charges
            end
        end
    end
    if reason then
        self:record_ability_decision(t, "dropped " .. resource_message(pending) .. ": " .. reason)
        return
    end
    return pending, held
end

function AlertHud:record_ability_decision(t, decision)
    local state = self._ability_state
    if state.decision == decision then
        return
    end
    state.decision, state.decided_at = decision, t
    if not mod:get("ability_diagnostics") then
        self._ability_history = nil
        return
    end
    local history = self._ability_history or {}
    self._ability_history = history
    if #history == 5 then
        table.remove(history, 1)
    end
    history[#history + 1] = {at = t, summary = decision}
end

local function describe_slot(extension, ability_type, slot, status)
    if not slot then
        return status or "no sample"
    end
    local function read(method)
        local fn = extension and extension[method]
        if type(fn) ~= "function" then
            return nil
        end
        local ok, value = pcall(fn, extension, ability_type)
        if ok then
            return value -- A valid false (not paused, not usable) stays false.
        end
    end
    local progress, paused, usable = read("get_ability_resource_regen_progress"),
        read("is_ability_resource_regen_paused"), read("can_use_ability")
    return string.format("%s %s/%s%s | usable %s | regen %s%s | %s", tostring(slot.name), tostring(slot.charges),
        tostring(slot.max), slot.ready == nil and "" or (slot.ready and " ready" or " not ready"),
        tostring(usable), type(progress) == "number" and string.format("%.0f%%", progress * 100) or "n/a",
        paused and " (paused)" or "", status or "")
end

function AlertHud:ability_diagnostics()
    local state = self._ability_state
    local t = self._draw_time or 0
    local extension = state.extension
    local waiting = {}
    for _, notice in ipairs(self._resource_queue or {}) do
        waiting[#waiting + 1] = string.format("%s (%.1fs%s)", resource_message(notice),
            math.max(0, notice.until_t - t), notice.held and ", unreadable" or "")
    end
    local decision = state.decision and string.format("%s %.1fs ago", state.decision, t - (state.decided_at or t))
        or "no alert yet"
    local history = {}
    for _, entry in ipairs(self._ability_history or {}) do
        history[#history + 1] = string.format("%.1fs: %s", t - entry.at, entry.summary)
    end
    local recent = #history > 0 and table.concat(history, " | ") or nil
    if not state.available then
        return mod:localize("ability_no_sample", state.combat_status or "no sample yet"), recent
    end
    return mod:localize("ability_sample",
        describe_slot(extension, "combat_ability", state.combat, state.combat_status),
        describe_slot(extension, "grenade_ability", state.grenade, state.blitz_status),
        #waiting > 0 and table.concat(waiting, ", ") or "none",
        decision), recent
end

function AlertHud:toughness_diagnostics()
    local state = self._toughness_state
    local t = self._draw_time or 0
    local history = {}
    for _, entry in ipairs(self._toughness_history or {}) do
        history[#history + 1] = string.format("%.1fs: %s", t - entry.at, entry.summary)
    end
    local recent = #history > 0 and table.concat(history, " | ") or nil
    local decision = state.decision and string.format("%s %.1fs ago", state.decision, t - (state.decided_at or t))
        or "no alert yet"
    if not state.percent then
        return mod:localize("toughness_no_sample", (state.sample or "no sample yet") .. " | " .. decision), recent
    end
    local extension = state.extension
    local vanilla_ok, vanilla = false, nil
    if extension and type(extension.current_toughness_percent) == "function" then
        vanilla_ok, vanilla = pcall(extension.current_toughness_percent, extension)
    end
    local vanilla_text = vanilla_ok and type(vanilla) == "number" and string.format("%.1f%%", vanilla * 100) or "n/a"
    return mod:localize("toughness_sample", state.remaining, state.maximum, state.percent, vanilla_text,
        state.threshold, state.recovery, state.armed and "armed" or "disarmed", state.max_changes or 0,
        state.sample or "no data", decision), recent
end

function AlertHud:mag_diagnostics()
    local ammo = self._ammo_state
    local t = self._draw_time or 0
    local threshold = mod:get("mag_threshold")
    local last_alert = ammo.mag_last_alert and string.format("%.1fs ago", t - ammo.mag_last_alert) or "none"
    local sample = ammo.mag_sample or "no sample yet"
    local decision = ammo.mag_decision or "no alert yet"
    local history = {}
    for _, entry in ipairs(self._mag_history or {}) do
        history[#history + 1] = string.format("%.1fs: %s", t - entry.at, entry.summary)
    end
    local recent = #history > 0 and table.concat(history, " | ") or nil
    if not ammo.slot then
        return mod:localize("mag_no_sample", threshold, sample), recent
    end
    return mod:localize("mag_sample", ammo.template.name or "unnamed", ammo.slot,
        ammo.mag, ammo.max_mag, ammo.mag * 100 / ammo.max_mag, threshold,
        ammo.mag_low and "disarmed" or "armed", last_alert, sample, decision), recent
end

function AlertHud:reserve_diagnostics()
    local ammo = self._ammo_state
    local displayed = self._live or self._preview
    local warning = ammo.reserve_warning
    local remaining = warning and warning.pending and math.max(0, warning.valid_until - (self._draw_time or 0)) or 0
    local decision = ammo.reserve_outcome or "no sample"
    local display = displayed and displayed.message or "none"
    local t = self._draw_time or 0
    local history = {}
    for _, entry in ipairs(self._supply_history or {}) do
        history[#history + 1] = string.format("%.1fs: %s", t - entry.at, entry.summary)
    end
    local recent = #history > 0 and table.concat(history, " | ") or nil
    if not ammo.slot or not ammo.max_reserve or ammo.max_reserve <= 0 then
        return mod:localize("reserve_no_sample", ammo.slot or "n/a", decision, display), recent
    end
    return mod:localize("reserve_sample", ammo.slot, ammo.equipped and "equipped" or "last ranged sample",
        ammo.total, ammo.max_total, 100 * ammo.total / ammo.max_total, ammo.reserve_threshold,
        ammo.mag, ammo.max_mag, ammo.reserve, ammo.max_reserve, ammo.supply_low and "disarmed" or "armed",
        remaining > 0 and "yes" or "no", remaining, display, decision), recent
end

function AlertHud:draw(dt, t, ui_renderer, render_settings, input_service)
    self._draw_time = t
    if mod.update_icons then
        mod.update_icons(t)
    end
    local unit, unit_data, loadout, toughness_extension, ability_extension, buff_extension
    if mod:is_enabled() then
        unit, unit_data, loadout, toughness_extension, ability_extension, buff_extension = self:preview_unit()
    end
    if not unit then
        self:clear_preview()
        self._live = nil
        -- Keep baselines while the same unit is netted, pounced or downed, so
        -- recovering from a disable doesn't silently re-baseline low values.
        local parent = self._parent
        local current = mod:is_enabled() and parent and parent.player_unit and parent:player_unit()
        if self._tracked_unit and current ~= self._tracked_unit then
            self:reset_live_alerts()
        end
        if mod.preview_element == self then
            mod.preview_element = nil
        end
        return
    end
    mod.preview_element = self

    if self._tracked_unit ~= unit then
        self:reset_live_alerts()
        self._tracked_unit = unit
    end
    local live = self._live
    if live and (not mod:get(live.key) or (live.expires_at and t >= live.expires_at)) then
        self._live = nil
    end
    self:sample_live(unit_data, t, loadout, toughness_extension, ability_extension, buff_extension)

    if not mod:get("preview") or (self._preview and self._preview.unit ~= unit) then
        self:clear_preview()
    end
    if self._live and self._preview and not self._preview.persistent then
        self:clear_preview()
    end
    local preview = self._live or self._preview
    if not preview then
        return
    end
    if not preview.started_at then
        preview.started_at = t
        if not preview.persistent then
            local duration_key = resource_keys[preview.key] and "ability_alert_duration"
                or preview.key and (preview.key .. "_duration") or "alert_duration"
            preview.expires_at = t + (urgent_keys[preview.key] and 2.5 or mod:get(duration_key))
        end
    end

    local opacity = 1
    if preview.expires_at then
        opacity = math.min(opacity, (preview.expires_at - t) / fade_out)
    end
    if preview.dismissed then
        preview.dismissed_at = preview.dismissed_at or t
        preview.dismissed_opacity = preview.dismissed_opacity or (preview.opacity or 0)
        opacity = math.min(opacity, preview.dismissed_opacity * (1 - (t - preview.dismissed_at) / fade_out))
    end
    if (preview.expires_at and t >= preview.expires_at)
        or (preview.dismissed and opacity <= 0) then
        self:clear_preview()
        return
    end

    preview.opacity = opacity
    local widget = self._widgets_by_name.alert
    widget.content.message = preview.message
    local base_size = mod:get(preview.key == "live_task" and "task_size" or "alert_size")
    local pop = 1 + 0.25 * math.max(0, 1 - (t - preview.started_at) / pop_time)
    local font_size = math.floor(base_size * pop + 0.5)
    widget.style.label.font_size = font_size
    local color = mod:get("category_colors") ~= false and palette[preview.key]
        or mod:get("alert_color") or default_color
    local text_color = widget.style.label.text_color
    text_color[1] = math.floor(opacity * 255 + 0.5)
    for i = 1, #outline_offsets do
        local outline = widget.style["outline_" .. i]
        outline.font_size = font_size
        outline.text_color[1] = text_color[1]
    end
    text_color[2], text_color[3], text_color[4] = color[2], color[3], color[4]
    layout(widget, preview.key, preview.message, font_size, opacity, color, ui_renderer)
    self:set_scenegraph_position("alert", 0, mod:get("alert_offset"), 5)
    AlertHud.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

function AlertHud:destroy(ui_renderer)
    if mod.preview_element == self then
        mod.preview_element = nil
    end
    AlertHud.super.destroy(self, ui_renderer)
end

return AlertHud
