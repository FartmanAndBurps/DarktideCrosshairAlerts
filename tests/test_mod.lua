local id = "DarktideCrosshairAlerts"
local descriptor = assert(loadfile(id .. "/" .. id .. ".mod"))()
local paths
function new_mod(name, provided_paths)
    assert(name == id)
    paths = provided_paths
end
descriptor.run()
for _, path in pairs(paths) do
    assert(loadfile(path .. ".lua"))
end

local hooks, settings = {}, {}
local mod = {enabled = true}
local originals, registrations = {}, 0
local external_mods = {}
function get_mod(name)
    if name ~= id then
        return external_mods[name] -- Other mods: nil unless a test installs one.
    end
    return mod
end
function mod:get(key) return settings[key] end
-- DMF keeps persistent tables across mod reloads (core/persistent_tables.lua).
local persistent_tables = {}
function mod:persistent_table(name, default)
    persistent_tables[name] = persistent_tables[name] or default or {}
    return persistent_tables[name]
end
function mod:is_enabled() return self.enabled end
function mod:localize(key, ...) return string.format(self.strings[key].en, ...) end
mod.require_callbacks = {}
function mod:hook_require(path, callback)
    self.require_callbacks[path] = callback
    if path:find("hud_element_crosshair", 1, true) then
        self.on_require = callback
    end
end
function mod:hook_safe(target, name, callback)
    if name == "stop" then
        -- Grenade and ammunition pickup markers.
        self.pickup_hooks = self.pickup_hooks or {}
        self.pickup_hooks[#self.pickup_hooks + 1] = {target = target, callback = callback}
        return
    end
    assert(name == "hot_join_sync")
    self.safe_hook_count = (self.safe_hook_count or 0) + 1
    self.hot_join_callback = callback
end
function mod:io_dofile(path) return dofile(path .. ".lua") end
function mod:hook(target, method, callback)
    local methods = originals[target] or {}
    assert(not methods[method], "duplicate hook on " .. method)
    local original = target[method]
    methods[method] = original
    originals[target] = methods
    registrations = registrations + 1
    target[method] = function(...)
        if self.enabled then
            return callback(original, ...)
        end
        return original(...)
    end
    hooks[method] = callback
end
function mod:register_hud_element(definition) self.hud = definition end
function mod:command(name, _, callback)
    local commands = {dca_preview = "preview", dca_reserve = "reserve_command", dca_mag = "mag_command",
        dca_toughness = "toughness_command", dca_ability = "ability_command"}
    self[assert(commands[name])] = callback
end
function mod:echo(message, ...)
    self.last_echo = string.format(message, ...)
    if self.capture_echo then
        self.capture_echo[#self.capture_echo + 1] = self.last_echo
    end
end

-- /dca_reserve prints a snapshot line, then a history line when there is one.
function mod:reserve_snapshot()
    self.capture_echo = {}
    self.reserve_command()
    local lines = self.capture_echo
    self.capture_echo = nil
    return lines[1] or "", lines[2]
end

mod.strings = dofile(paths.mod_localization .. ".lua")
local ok, failure = pcall(string.format, "Dot opacity (%)")
assert(not ok and failure:find("%)", 1, true))
assert(mod:localize("dot_opacity") == "Dot opacity (%)")
local localization_args = {
    mag_sample = {"shotgun", "slot_secondary", 2, 10, 20, 20, "armed", "none", "new baseline", "no alert yet"},
    mag_no_sample = {20, "no active HUD"},
    reserve_sample = {"slot_secondary", "equipped", 7, 50, 14, 15, 2, 10, 5, 40, "disarmed", "no", 0, "AMMO LOW", "emitted"},
    reserve_no_sample = {"n/a", "no active HUD", "none"},
    toughness_sample = {37.5, 150, 25, "25.0%", 25, 50, "armed", 0, "armed", "no alert yet"},
    toughness_no_sample = {"no active HUD"},
    ability_no_sample = {"no active HUD"},
    ability_sample = {"combat", "grenade", "none", "no alert yet"},
    alert_grenade = {2},
    alert_blitz = {1},
    alert_stimm = {3},
}
assert(mod:localize("alert_grenade", 2) == "GRENADE +2" and mod:localize("alert_ability") == "ABILITY READY")
assert(mod:localize("reserve_sample", unpack(localization_args.reserve_sample)):find("total 7/50 (14.0%) | threshold 15% | mag 2/10 reserve 5/40", 1, true))
assert(mod:localize("alert_mag") == "RELOAD" and mod:localize("alert_ammo") == "AMMO LOW" and not mod.strings.alert_mag_short)
for key, translations in pairs(mod.strings) do
    for language, template in pairs(translations) do
        local valid, result = pcall(string.format, template, unpack(localization_args[key] or {}))
        assert(valid, key .. "/" .. language .. ": " .. result)
    end
end
print("PASS: reproduced old localization error and formatted every current translation")

local data = dofile(paths.mod_data .. ".lua")
assert(data.is_togglable)
local options = {}
local function register_widgets(widgets, depth)
    assert(depth <= 2)
    for _, option in ipairs(widgets) do
        local key = option.setting_id
        assert(not options[key] and mod:localize(key) ~= "")
        options[key] = option
        if option.type == "group" then
            assert(depth == 0 and option.default_value == nil and #option.sub_widgets > 0)
        elseif settings[key] == nil then
            assert(option.default_value ~= nil)
            settings[key] = option.default_value
        end
        if option.sub_widgets then
            assert(option.type == "group" or option.type == "checkbox")
            register_widgets(option.sub_widgets, depth + 1)
        end
    end
end
assert(#data.options.widgets == 8)
-- A player upgrading from 0.5.x still has the removed Peril & Heat values saved.
settings.live_peril, settings.peril_threshold, settings.live_overheat = true, 85, true
settings.heat_threshold, settings.heat_diagnostics = 85, true
register_widgets(data.options.widgets, 0)
local existing_ids = {
    "crosshair", "dot_color", "dot_size", "dot_opacity", "live_task", "live_low_mag", "mag_threshold",
    "live_low_ammo", "reserve_threshold", "preview", "preview_key", "alert_color", "alert_offset",
    "alert_size", "task_size", "live_task_duration", "live_low_mag_duration", "live_low_ammo_duration",
    "mag_diagnostics", "reserve_diagnostics", "alert_duration", "live_toughness", "live_broken",
    "toughness_threshold", "toughness_recovery",
}
for _, key in ipairs(existing_ids) do
    assert(options[key], key)
end
assert(settings.live_toughness and not settings.live_broken
    and settings.toughness_threshold == 25 and settings.toughness_recovery == 50)
assert(options.live_broken.sub_widgets == nil and #options.live_toughness.sub_widgets == 2)
-- New 0.3.1 controls nest in their existing groups and default sensibly.
assert(settings.mag_min_rounds == 1 and not settings.toughness_diagnostics)
assert(options.live_low_mag.sub_widgets[2].setting_id == "mag_min_rounds")
assert(options.group_testing.sub_widgets[4].setting_id == "toughness_diagnostics")
-- 0.6.0: Peril & Heat is gone; Abilities & Blitz sits before Testing & Diagnostics.
assert(data.options.widgets[6].setting_id == "group_abilities" and data.options.widgets[8].setting_id == "group_testing")
-- 0.7.0: a small Stimm group between Abilities & Blitz and Testing, with one toggle and its threshold.
assert(data.options.widgets[7].setting_id == "group_stimm" and #options.group_stimm.sub_widgets == 1)
assert(settings.live_stimm == true and settings.stimm_threshold == 3)
-- 0.8.0: one display-mode dropdown under Appearance, Icon + text by default.
assert(options.group_appearance.sub_widgets[5].setting_id == "alert_display" and settings.alert_display == "icon_text")
assert(options.alert_display.type == "dropdown" and #options.alert_display.options == 3)
for _, option in ipairs(options.alert_display.options) do
    assert(mod:localize(option.text) ~= option.text and (option.value == "text" or option.value == "icon" or option.value == "icon_text"))
end
assert(#options.live_stimm.sub_widgets == 1 and options.stimm_threshold.range[1] == 1 and options.stimm_threshold.range[2] == 10)
for _, removed in ipairs({"group_peril_heat", "live_peril", "peril_threshold", "live_overheat", "heat_threshold",
    "heat_diagnostics"}) do
    assert(not options[removed] and not mod.strings[removed], removed)
end
for key in pairs(mod.strings) do
    assert(not key:find("peril", 1, true) and not key:find("heat", 1, true), key)
end
assert(#options.group_testing.sub_widgets == 5)
-- One category-colour toggle under Appearance, on by default; the saved colour stays the TASK/preview colour.
assert(options.group_appearance.sub_widgets[4].setting_id == "category_colors" and settings.category_colors == true)
assert(settings.live_ability and settings.live_blitz and settings.live_dog and settings.ability_alert_duration == 2
    and not settings.ability_diagnostics)
assert(#options.group_abilities.sub_widgets == 4 and options.group_testing.sub_widgets[5].setting_id == "ability_diagnostics")
-- Model the DMF upgrade rule that initializes only unset saved settings.
local saved_color = {255, 230, 90, 255}
settings.dot_color, settings.crosshair = saved_color, false
options = {}
register_widgets(data.options.widgets, 0)
assert(settings.dot_color == saved_color and settings.crosshair == false)
settings.crosshair = true
print("PASS: eight native groups incl. Stimm, removed Peril & Heat, category colours, existing setting IDs, new defaults and saved settings")
assert(settings.crosshair and settings.preview)
assert(settings.dot_size == 6 and settings.dot_opacity == 100)
assert(settings.alert_size == 23 and settings.task_size == 26 and settings.alert_offset == 60 and settings.alert_duration == 2)
assert(options.alert_color.type == "color" and table.concat(settings.alert_color, ",") == "255,255,245,107")
assert(settings.live_task_duration == 5 and settings.live_low_mag_duration == 2.5
    and settings.live_low_ammo_duration == 2.5 and not settings.reserve_diagnostics)
assert(settings.reserve_threshold == 25 and settings.mag_threshold == 20 and not settings.mag_diagnostics)
-- Model an upgrading player whose stored reserve threshold is still 15%.
settings.reserve_threshold = 15
dofile(paths.mod_script .. ".lua")
mod.mag_command()
assert(mod.last_echo == mod:localize("mag_diagnostics_off"))
mod.reserve_command()
assert(mod.last_echo == mod:localize("reserve_diagnostics_off"))
mod.toughness_command()
assert(mod.last_echo == mod:localize("toughness_diagnostics_off"))
mod.ability_command()
assert(mod.last_echo == mod:localize("ability_diagnostics_off"))
assert(mod.heat_command == nil) -- /dca_heat is no longer registered.
mod.on_require({})
assert(next(hooks) == nil)
local function class_target()
    return {
        _get_current_crosshair_type = function(_, settings) return settings.original end,
        _draw_widgets = function() end,
    }
end
local first, second = class_target(), class_target()
mod.on_require(first)
mod.on_require(first)
assert(registrations == 2)
mod.on_require(second)
mod.on_require(first)
mod.on_require(second)
assert(registrations == 4)
-- Model DMF restoring class methods and recreating its registry on a full reload.
for target, methods in pairs(originals) do
    for method, original in pairs(methods) do
        target[method] = original
    end
end
originals = {}
dofile(paths.mod_script .. ".lua")
mod.on_require(first)
mod.on_require(first)
assert(registrations == 6)
assert(mod.hud.visibility_groups[1] == "alive")
assert(mod.hud.allowed_game_modes[2] == "shooting_range")

local alternate = {is_active = false}
local unit = {}
local state = {state_name = "walking"}
local disabled = {is_disabled = false}
-- Alternate-fire crosshairs copied from the inspected weapon templates.
local alt_templates = {
    autogun_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "ironsight"}}},
    lasgun_p2_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "charge_up_ads"}}},
    ogryn_gauntlet_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "projectile_drop"}}},
    ogryn_heavystubber_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "spray_n_pray"}}},
    shotpistol_shield_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type_func = function() return "shotgun" end}}},
    forcestaff_p1_m1 = {},
    -- From the inspected templates: the Arc Rifle uses bfg for hip fire and bracing.
    arc_rifle_p1_m1 = {keywords = {"ranged", "arc_rifle", "p1"},
        alternate_fire_settings = {crosshair = {crosshair_type = "bfg"}}},
    plasmagun_p1_m1 = {keywords = {"ranged", "plasmagun", "p1"}},
    lasgun_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "ironsight"}}},
    shotgun_p4_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "shotgun_wide"}}},
    flamer_p1_m1 = {alternate_fire_settings = {crosshair = {crosshair_type = "flamer"}}},
    saw_p1_m1 = {},
    ogryn_thumper_p1_m2 = {alternate_fire_settings = {crosshair = {crosshair_type = "ironsight"}}},
    boltpistol_p1_m1 = {keywords = {"ranged", "boltpistol", "p1"},
        alternate_fire_settings = {crosshair = {crosshair_type = "ironsight"}}},
}
local weapon_action = {template_name = "shotpistol_shield_p1_m1"}
package.loaded["scripts/utilities/weapon/weapon_template"] = {
    current_weapon_template = function(action) return alt_templates[action.template_name] end,
}
local components = {
    alternate_fire = alternate,
    character_state = state,
    disabled_character_state = disabled,
    weapon_action = weapon_action,
}
local extensions = {
    unit = unit,
    unit_data = {read_component = function(_, name) return assert(components[name]) end},
}
local parent = {
    player_extensions = function() return extensions end,
    player_unit = function() return unit end,
}
local reticle = {
    _parent = parent,
    _crosshair_templates = {dot = {}},
    _crosshair_widget_definitions = {dot = {}},
}
local resolve = hooks._get_current_crosshair_type
local function check_type(original, expected)
    assert(resolve(function() return original end, reticle, {}) == expected)
end
-- 0.6.1 dot-first: each case is a weapon from the inspected templates, its aim
-- state, the type vanilla resolves, and what the player should see.
local matrix = {
    {"autogun_p1_m1", false, "assault", "dot"}, {"autogun_p1_m1", true, "ironsight", "ironsight"},
    {"lasgun_p1_m1", false, "cross", "dot"}, {"lasgun_p1_m1", true, "ironsight", "ironsight"},
    {"ogryn_heavystubber_p1_m1", false, "spray_n_pray", "dot"}, {"ogryn_heavystubber_p1_m1", true, "spray_n_pray", "dot"},
    {"shotpistol_shield_p1_m1", false, "shotgun", "dot"}, {"shotpistol_shield_p1_m1", true, "shotgun", "dot"},
    {"shotgun_p4_m1", false, "shotgun_wide", "dot"}, {"shotgun_p4_m1", true, "shotgun_wide", "dot"},
    {"arc_rifle_p1_m1", false, "bfg", "dot"}, {"arc_rifle_p1_m1", true, "bfg", "dot"},
    {"plasmagun_p1_m1", false, "bfg", "dot"}, -- Previously excluded.
    {"boltpistol_p1_m1", false, "bfg", "dot"}, {"boltpistol_p1_m1", true, "ironsight", "ironsight"},
    {"flamer_p1_m1", false, "flamer", "dot"}, {"flamer_p1_m1", true, "flamer", "dot"}, -- Previously excluded.
    {"saw_p1_m1", false, "dot_special", "dot"}, -- Previously excluded.
    {"forcestaff_p1_m1", false, "charge_up", "charge_up"}, -- Charge bars kept.
    {"lasgun_p2_m1", false, "bfg", "dot"}, {"lasgun_p2_m1", true, "charge_up_ads", "charge_up_ads"},
    {"ogryn_gauntlet_p1_m1", true, "projectile_drop", "projectile_drop"}, -- Drop ladder kept.
    {"ogryn_thumper_p1_m2", false, "projectile_drop", "projectile_drop"},
    {"shotpistol_shield_p1_m1", false, "none", "none"}, -- Reload: no reticle by design.
    {"shotpistol_shield_p1_m1", false, "dot", "dot"}, -- Empty cylinder and bash.
    {"future_weapon", false, "future_type", "dot"}, -- Unknown types default to the dot.
}
for _, case in ipairs(matrix) do
    weapon_action.template_name, alternate.is_active = case[1], case[2]
    local got = resolve(function() return case[3] end, reticle, {})
    assert(got == case[4], ("%s %s %s: got %s"):format(case[1], case[2] and "alt" or "hip", case[3], tostring(got)))
end
alternate.is_active = false
-- Every vanilla template (HudElementCrosshairSettings.templates) plus "none" is covered.
local vanilla_types = {"assault", "bfg", "charge_up_ads", "charge_up", "cross", "dot", "dot_special", "flamer",
    "ironsight", "projectile_drop", "shotgun_wide", "shotgun", "spray_n_pray", "none"}
local preserved_types = {charge_up = true, charge_up_ads = true, ironsight = true, projectile_drop = true, none = true}
for _, kind in ipairs(vanilla_types) do
    check_type(kind, preserved_types[kind] and kind or "dot")
end
-- Unreadable weapon or aim state never blocks the rule: it depends only on the resolved type.
components.weapon_action = nil
check_type("bfg", "dot")
check_type("ironsight", "ironsight")
components.weapon_action = weapon_action
weapon_action.template_name = "shotpistol_shield_p1_m1"
-- Replacement off restores every vanilla type.
settings.crosshair = false
for _, kind in ipairs(vanilla_types) do
    check_type(kind, kind)
end
settings.crosshair = true
assert(first._get_current_crosshair_type(reticle, {original = "shotgun"}) == "dot")
mod.enabled = false
assert(first._get_current_crosshair_type(reticle, {original = "shotgun"}) == "shotgun")
mod.enabled = true
assert(first._get_current_crosshair_type(reticle, {original = "shotgun"}) == "dot")
assert(registrations == 6)
reticle._crosshair_widget_definitions.dot = nil
check_type("cross", "cross")
reticle._crosshair_widget_definitions.dot = {}
components.alternate_fire = nil
check_type("cross", "dot") -- Type replacement no longer depends on reading the aim state.
components.alternate_fire = alternate

local size, color, hit, charge = {4, 4}, {255, 255, 255, 255}, {}, {}
local centre = {size = size, color = color}
reticle._widget = {style = {center = centre, hit_top_left = hit, charge_left = charge}}
local draw = hooks._draw_widgets
local function check_draw(expected_alpha, expected_size)
    local calls = 0
    draw(function(element)
        calls = calls + 1
        assert(element == reticle)
        assert(element._widget.style.hit_top_left == hit)
        assert(element._widget.style.charge_left == charge)
        assert(centre.color[1] == expected_alpha and centre.size[1] == expected_size)
        if expected_size == 6 then
            local saved = settings.dot_color
            assert(centre.color[2] == saved[2] and centre.color[3] == saved[3] and centre.color[4] == saved[4])
        end
    end, reticle)
    assert(calls == 1 and centre.color == color and centre.size == size)
end
reticle._crosshair_type = "dot"
settings.dot_color = {255, 245, 106, 230}
settings.dot_opacity = 50
check_draw(128, 6)
alternate.is_active = true
for _, braced in ipairs({"shotpistol_shield_p1_m1", "ogryn_heavystubber_p1_m1"}) do
    weapon_action.template_name = braced
    check_draw(128, 6) -- Braced: same custom dot as hip fire.
end
for _, sighted in ipairs({"autogun_p1_m1", "lasgun_p2_m1", "ogryn_gauntlet_p1_m1"}) do
    weapon_action.template_name = sighted
    check_draw(0, 6) -- A vanilla dot during true ADS is hidden.
end
weapon_action.template_name = "unknown_template"
check_draw(128, 6) -- An unreadable alternate-fire template is treated as braced.
for _, braced in ipairs({"arc_rifle_p1_m1", "flamer_p1_m1", "shotgun_p4_m1"}) do
    weapon_action.template_name = braced
    check_draw(128, 6) -- Braced or spread alternate fire: the dot stays visible.
end
reticle._crosshair_type = "charge_up"
weapon_action.template_name = "autogun_p1_m1"
check_draw(0, 6) -- Charge bars stay; only the centre hides while sighted.
alternate.is_active = false
weapon_action.template_name = "forcestaff_p1_m1"
check_draw(128, 6) -- Charging staff centre now uses the custom dot.
components.alternate_fire = nil
check_draw(255, 4) -- Unreadable aim state leaves vanilla untouched.
components.alternate_fire = alternate
weapon_action.template_name = "shotpistol_shield_p1_m1"
reticle._crosshair_type = "dot"
assert(not pcall(draw, function() error("draw failed") end, reticle))
assert(centre.color == color and centre.size == size)
settings.crosshair = false
check_type("cross", "cross")
check_draw(255, 4)
print("PASS: descriptor, options, repeated require, reload, dot-first remap across all vanilla reticles, brace, ADS and restoration")

package.loaded["scripts/managers/ui/ui_widget"] = {create_definition = function(passes) return passes end}
package.loaded["scripts/settings/ui/ui_workspace_settings"] = {screen = {}}
package.loaded["scripts/utilities/attack/player_unit_status"] = {
    is_disabled = function(component) return component.state_name == "knocked_down" end,
}
local base = {
    init = function(self, parent, _, _, definitions)
        self._parent = parent
        assert(definitions.scenegraph_definition.alert.parent == "screen")
        local passes = definitions.widget_definitions.alert
        assert(#passes == 10)
        local style = {}
        for i, pass in ipairs(passes) do
            -- Four outline passes and the label, then four icon outline passes and
            -- the icon: texture passes on vanilla's default UI material, whose
            -- texture_map is the loaded artwork. No rect pass: the 0.9.0 AMMO LOW
            -- underline is gone (0.9.1).
            assert(not style[pass.style_id], pass.style_id)
            assert(pass.pass_type ~= "rect" and pass.style_id ~= "marker", "no underline pass")
            if i <= 5 then
                assert(pass.pass_type == "text" and pass.value_id == "message" and pass.visibility_function)
            else
                assert(i <= 10 and pass.pass_type == "texture" and pass.value == "content/ui/materials/base/ui_default_base"
                    and pass.style_id == (i == 10 and "icon" or "icon_outline_" .. (i - 5))
                    and pass.visibility_function and pass.style.material_values
                    and pass.style.material_values.use_placeholder_texture == 0
                    and pass.style.material_values.texture_map == nil, pass.style_id)
            end
            -- Like UIWidget.init, each widget gets its own copy of the styles.
            local function copy(value)
                if type(value) ~= "table" then
                    return value
                end
                local result = {}
                for k, v in pairs(value) do
                    result[k] = copy(v)
                end
                return result
            end
            style[pass.style_id] = copy(pass.style)
        end
        self._alert_passes = passes
        self._widgets_by_name = {alert = {content = {}, style = style}}
    end,
    -- Records which passes the real renderer would draw this frame.
    draw = function(self)
        self.draws = (self.draws or 0) + 1
        local widget = self._widgets_by_name.alert
        local rendered = {}
        for _, pass in ipairs(self._alert_passes) do
            if not pass.visibility_function or pass.visibility_function(widget.content, widget.style[pass.style_id]) then
                rendered[pass.style_id] = true
            end
        end
        self.rendered = rendered
    end,
    destroy = function() end,
    set_scenegraph_position = function(self, _, x, y)
        assert(x == 0 and y == settings.alert_offset)
    end,
}
function class() return setmetatable({super = base}, {__index = base}) end

-- Simple Assets stand-in. load_textures returns a promise the test settles,
-- resolving each input path like Simple Assets does: the real PNG must exist
-- at the mod path, and its texture is a table standing in for the userdata.
local Deferred = {}
Deferred.__index = Deferred
function Deferred.new() return setmetatable({handlers = {}}, Deferred) end
function Deferred:_flush()
    local handlers = self.handlers
    self.handlers = {}
    for _, handler in ipairs(handlers) do
        local callback = self.state == "ok" and handler.ok or self.state == "err" and handler.err
        if callback then
            local ok, result = pcall(callback, self.value)
            if ok then handler.child:resolve(result) else handler.child:reject(result) end
        elseif self.state == "ok" then
            handler.child:resolve(self.value)
        else
            handler.child:reject(self.value)
        end
    end
end
function Deferred:next(ok, err)
    local child = Deferred.new()
    self.handlers[#self.handlers + 1] = {ok = ok, err = err, child = child}
    if self.state then self:_flush() end
    return child
end
function Deferred:catch(err)
    local child = Deferred.new()
    self.handlers[#self.handlers + 1] = {err = err, child = child}
    if self.state then self:_flush() end
    return child
end
function Deferred:resolve(value) self.state, self.value = "ok", value; self:_flush() end
function Deferred:reject(value) self.state, self.value = "err", value; self:_flush() end

local function png_header(file)
    local handle = io.open(file, "rb")
    if not handle then
        return
    end
    local data = handle:read(26)
    handle:close()
    local function u32(at)
        local a, b, c, d = data:byte(at, at + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return {signature = data:sub(1, 8), width = u32(17), height = u32(21), colour_type = data:byte(26)}
end
mod.png_header = png_header

function mod.new_simple_assets(options)
    options = options or {}
    -- files counts requested files however they are grouped into load_textures calls.
    local simple_assets = {files = 0, paths = {}, open = {}}
    function simple_assets.load_textures(paths)
        simple_assets.files = simple_assets.files + #paths
        if options.throw then
            error(options.throw)
        end
        local request = {paths = paths, promise = Deferred.new()}
        for _, path in ipairs(paths) do simple_assets.paths[#simple_assets.paths + 1] = path end
        simple_assets.open[#simple_assets.open + 1] = request
        return request.promise
    end
    function simple_assets.settle(missing)
        local open = simple_assets.open
        simple_assets.open = {}
        for _, request in ipairs(open) do
            local results = {}
            for _, path in ipairs(request.paths) do
                local header = png_header(path:gsub("^mods/", ""))
                if header and not (missing and missing[path]) then
                    results[path] = {is_ok = true, url = "simpleassets://" .. path, texture = {path = path},
                        width = header.width, height = header.height}
                else
                    results[path] = {is_ok = false, url = "simpleassets://" .. path}
                end
            end
            request.promise:resolve(results)
        end
    end
    function simple_assets.reject(value)
        local open = simple_assets.open
        simple_assets.open = {}
        for _, request in ipairs(open) do request.promise:reject(value) end
    end
    return simple_assets
end
function mod.set_external_mod(name, value) external_mods[name] = value end
-- A fresh icon module, as after a mod load; optionally with Simple Assets installed and loaded.
function mod.reset_icons(simple_assets, settle)
    mod.icons = dofile("DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/icon_textures.lua")
    external_mods.SimpleAssets = simple_assets
    if simple_assets and settle then
        mod.request_icons()
        simple_assets.settle()
        assert(mod.icons.state.status == "ready")
    end
    return mod.icons
end

-- Rendering check for every drawn alert, in whichever display mode is set.
local icon_prefixes = {{"TASK", "live_task"}, {"RELOAD", "live_low_mag"}, {"AMMO LOW", "live_low_ammo"},
    {"TOUGHNESS", "live_toughness"}, {"BROKEN", "live_broken"}, {"ABILITY READY", "live_ability"},
    {"GRENADE +", "live_blitz"}, {"BLITZ +", "live_blitz"}, {"DOG READY", "live_dog"}, {"STIM ", "live_stimm"}}
function mod.icon_key_for(message)
    for _, entry in ipairs(icon_prefixes) do
        if message:sub(1, #entry[1]) == entry[1] then
            return entry[2]
        end
    end
end
local icon_ids = {"icon_outline_1", "icon_outline_2", "icon_outline_3", "icon_outline_4", "icon"}
function mod.check_icons(hud, message, render_scale)
    local widget = hud._widgets_by_name.alert
    local content, style, rendered = widget.content, widget.style, hud.rendered
    local key = mod.icon_key_for(message)
    local mode = settings.alert_display
    local label = style.label
    local size = 28 * (label.font_size / 23)
    local texture = mode ~= "text" and key and mod.icons and mod.icons.texture(key, size * (render_scale or 1)) or nil
    assert(content.message == message and content.icon_texture == texture,
        ("%s in %s: texture %s"):format(message, tostring(mode), tostring(content.icon_texture)))
    if texture then
        local expected_size = size * (render_scale or 1) > 64 and 128 or 64
        assert(texture.path == mod.icons.path(expected_size, key) or texture.path == mod.icons.path(192 - expected_size, key),
            message .. " uses its own artwork")
    end
    local text_shown = rendered.label == true
    assert(text_shown == (mode ~= "icon" or texture == nil), message .. " text visibility in " .. tostring(mode))
    for i = 1, 4 do
        assert(rendered["outline_" .. i] == rendered.label)
    end
    for _, icon_id in ipairs(icon_ids) do
        assert((rendered[icon_id] == true) == (texture ~= nil), icon_id .. " drawn only with a texture")
    end
    if not texture then
        assert(label.offset[1] == 0 and style.outline_1.offset[1] == -2 and style.outline_2.offset[1] == 2,
            message .. " text layout unchanged")
        return
    end
    local icon = style.icon
    for i, icon_id in ipairs(icon_ids) do
        local part = style[icon_id]
        assert(part.material_values.texture_map == texture and math.abs(part.size[1] - size) < 1e-9
            and part.size[1] == part.size[2])
        assert(part.color[1] == label.text_color[1], icon_id .. " fades with the text")
        if icon_id == "icon" then
            assert(part.color[2] == label.text_color[2] and part.color[3] == label.text_color[3]
                and part.color[4] == label.text_color[4], "icon tinted with the alert colour")
            assert(part.offset[2] == 0 and part.offset[3] == 2)
        else
            assert(part.color[2] == 8 and part.color[3] == 6 and part.color[4] == 3 and part.offset[3] == 1)
            assert(math.abs(math.abs(part.offset[1] - icon.offset[1]) + math.abs(part.offset[2]) - 1.5) < 1e-9)
        end
    end
    if text_shown then
        -- Icon on the left, text on the right, the pair centred, no overlap.
        local width = hud.measured_width or #message * label.font_size * 0.6
        local text_left, text_right = label.offset[1] - width / 2, label.offset[1] + width / 2
        local icon_left, icon_right = icon.offset[1] - size / 2, icon.offset[1] + size / 2
        assert(math.abs(icon_left + text_right) < 1e-6, message .. " pair is centred")
        assert(icon_right + 1.5 < text_left, message .. " icon overlaps text")
        assert(style.outline_1.offset[1] == label.offset[1] - 2 and style.outline_4.offset[1] == label.offset[1])
    else
        assert(icon.offset[1] == 0, message .. " icon centred")
    end
end
mod.check_symbols = mod.check_icons

local hud = setmetatable({}, {__index = dofile(mod.hud.filename .. ".lua")})
hud:init(parent, 0, 1)
mod:preview()
assert(mod.last_echo)
hud:draw(0, 0)
assert(mod.preview_element == hud and not hud.draws)
mod.preview_brief()
local widget = hud._widgets_by_name.alert
local function frame(time, alpha)
    local before = hud.draws or 0
    hud:draw(0, time)
    if alpha then
        assert(hud.draws == before + 1 and math.abs(widget.style.label.text_color[1] - alpha) <= 1)
    else
        assert((hud.draws or 0) == before)
    end
end
frame(1, 255)
assert(widget.content.message == "TEST ALERT")
assert(widget.style.label.font_size == 29 and widget.style.label.drop_shadow)
local function check_rgb(expected)
    local color = widget.style.label.text_color
    assert(table.concat(color, ",", 2, 4) == expected)
end
check_rgb("255,245,107")
frame(1.09, 255)
assert(widget.style.label.font_size == 26)
frame(1.2, 255)
assert(widget.style.label.font_size == 23 and widget.style.outline_1.font_size == 23)
frame(2.91, 128)
for i = 1, 4 do
    assert(widget.style["outline_" .. i].text_color[1] == widget.style.label.text_color[1])
end
frame(3)
assert(not hud._preview)
mod.preview("hold")
local saved_color = {255, 240, 110, 160}
settings.alert_color = saved_color
settings.alert_size, settings.alert_offset = 23, 68
frame(10, 255)
frame(300, 255)
check_rgb("240,110,160")
assert(widget.style.label.font_size == 23 and saved_color[1] == 255)
settings.alert_color = nil
frame(300.1, 255)
check_rgb("255,245,107")
assert(hud._preview.persistent and widget.content.message == "TEST WARNING")
mod.preview("clear")
frame(301, 255)
frame(301.09, 128)
frame(301.2)
assert(not hud._preview)
mod.preview("hold")
disabled.is_disabled = true
frame(302)
assert(not hud._preview and not mod.preview_element)
disabled.is_disabled = false
frame(303)
mod.preview("hold")
mod.enabled = false
mod.on_disabled()
frame(304)
assert(not hud._preview)
mod.enabled = true
frame(305)
mod.preview("hold")
unit = {}
extensions.unit = unit
frame(306)
assert(not hud._preview)
hud:destroy()
assert(not mod.preview_element)
print("PASS: text-only fixed anchor, fades, expiry, persistent preview and lifecycle")

function mod:test_live_hud(device, map, ammo_components, slot)
    local holder = {}
    local data = {read_component = function(_, name)
        return ammo_components[name] or assert(components[name])
    end}
    local live_parent = {
        player_unit = function() return holder.unit end,
        player_extensions = function() return {unit = holder.unit, unit_data = data} end,
    }
    local live_hud = setmetatable({}, {__index = dofile(self.hud.filename .. ".lua")})
    live_hud:init(live_parent, 0, 1)
    local live_widget = live_hud._widgets_by_name.alert
    local label = live_widget.content
    settings.live_low_mag_duration = 2.7
    settings.live_low_ammo_duration = 3.25
    settings.live_task_duration = 5.1
    settings.reserve_diagnostics = true
    settings.preview = false
    map.a, map.b, map.bad, map.joined = device, nil, nil, nil
    device.interrupted = false
    slot.clips[1], slot.reserve = 1, 10
    live_hud:draw(0, 0)
    assert(not live_hud.draws)
    holder.unit = {}
    live_hud:draw(0, 1)
    assert(not live_hud.draws)
    slot.clips[1], slot.reserve = 3, 20
    live_hud:draw(0, 1.2)
    slot.clips[1], slot.reserve = 1, 14
    live_hud:draw(0, 1.4)
    assert(label.message == "RELOAD")
    assert(math.abs(live_hud._live.expires_at - 4.1) < 0.001)
    assert(mod:reserve_snapshot():find("deferred by higher priority", 1, true))
    device.interrupted = true
    live_hud:draw(0, 1.6)
    assert(label.message == "TASK" and live_widget.style.label.font_size == 33)
    assert(math.abs(live_hud._live.expires_at - 6.7) < 0.001)
    live_hud:draw(0, 6.8)
    assert(label.message == "AMMO LOW")
    assert(math.abs(live_hud._live.expires_at - 10.05) < 0.001)
    local snapshot, history = mod:reserve_snapshot()
    assert(snapshot:find("total 15/110 (13.6%)", 1, true) and snapshot:find("mag 1/10 reserve 14/100", 1, true)
        and snapshot:find("emitted", 1, true), snapshot)
    assert(history and history:find("23/110 rearmed", 1, true) and history:find("15/110 deferred by higher priority", 1, true), history)
    local before = live_hud.draws
    holder.unit = nil
    live_hud:draw(0, 7)
    holder.unit = {}
    live_hud:draw(0, 7.2)
    assert(live_hud.draws == before)
    live_hud:destroy()
    local next_hud = setmetatable({}, {__index = getmetatable(live_hud).__index})
    next_hud:init(live_parent, 0, 1)
    next_hud:draw(0, 8)
    assert(next_hud._widgets_by_name.alert.content.message == "TASK")
    next_hud:destroy()
    print("PASS: live HUD context, initial suppression, TASK preemption, unit reset and HUD recreation")
end

function mod:test_ammo_timelines(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local live_hud, unit, ranged_item
    local melee = {melee = true}
    local toughness = {maximum = 100, remaining = 100,
        max_toughness = function(self) return self.maximum end,
        remaining_toughness = function(self) return self.remaining end}
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local loadout = {item_from_slot = function() return ranged_item end}
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function() return {unit = unit, unit_data = data, visual_loadout = loadout, toughness = toughness} end,
    }
    local function wield(slot_name, equipped_template, kind)
        inventory.wielded_slot, action.slot_name = slot_name, slot_name
        action.template, action.current_action_name = equipped_template, kind or "none"
    end
    local function frame(t, expected)
        local previous = live_hud.draws or 0
        live_hud:draw(0, t)
        local actual
        if live_hud.draws ~= previous then
            actual = live_hud._widgets_by_name.alert.content.message
            if actual then
                mod.check_symbols(live_hud, actual)
            end
        end
        assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
    end
    local function reset()
        if live_hud then
            live_hud:destroy()
        end
        unit, ranged_item = {}, {}
        toughness.remaining = 100
        live_hud = setmetatable({}, {__index = hud_class})
        live_hud:init(parent, 0, 1)
        map.a = device
        device.interrupted = false
        slot.clips[1], slot.clips[2], slot.reserve = 5, 0, 20
        wield("slot_secondary", template)
        settings.live_task_duration, settings.live_low_mag_duration, settings.live_low_ammo_duration = 5, 2.5, 2.5
        frame(0)
    end

    settings.mag_diagnostics = true
    reset()
    slot.clips[1] = 3
    frame(0.2) -- 3/10 is above 20%, so it is armed; 2/10 now counts as low.
    wield("slot_luggable", {}, "none")
    frame(0.4) -- Carry the power cell.
    ammo_components.weapon_action = nil
    frame(0.52) -- Carrying preserves the baseline even without a weapon action component.
    ammo_components.weapon_action = action
    wield("none", {}, "none")
    action.template_name = "none"
    frame(0.64) -- Enemy hit drops the power cell.
    action.template_name = nil
    wield("slot_secondary", template, "action_wield")
    frame(0.8) -- Re-equipped with three shells, still in the wield transition.
    wield("slot_secondary", template, "action_shoot")
    slot.clips[1] = 1
    frame(1.0, "RELOAD") -- The first usable ranged sample follows the shot.
    self.capture_echo = {}
    self.mag_command()
    assert(#self.capture_echo == 2)
    assert(self.capture_echo[1]:find("1/10 (10.0%)", 1, true) and self.capture_echo[1]:find("emitted", 1, true))
    assert(self.capture_echo[2]:find("luggable", 1, true) and self.capture_echo[2]:find("switching", 1, true))
    self.capture_echo = nil
    wield("slot_primary", melee)
    frame(1.2)
    wield("slot_secondary", template)
    frame(1.4) -- Re-equipping at one shell alone is silent.
    wield("slot_primary", melee)
    frame(1.6)
    wield("slot_secondary", template)
    frame(1.8)

    reset()
    slot.clips[1] = 3
    frame(0.2)
    wield("slot_secondary", template, "action_reload_shell")
    slot.clips[1] = 1
    frame(0.4) -- A decrease during reload is suppressed.
    wield("slot_secondary", template, "action_reload_shell")
    slot.clips[1] = 2
    frame(0.6) -- Loading to exactly 20% is still low and stays disarmed.
    slot.clips[1] = 3
    frame(0.8) -- Above the threshold rearms.
    wield("slot_secondary", template, "action_shoot")
    slot.clips[1] = 1
    frame(1.0, "RELOAD")

    reset()
    device.interrupted = true
    frame(0.2, "TASK")
    slot.reserve = 10 -- (Stub jump.) Firing takes the total to 15 of 110.
    wield("slot_secondary", template, "action_shoot")
    frame(0.4, "TASK")
    local snapshot = self:reserve_snapshot()
    assert(snapshot:find("mag 5/10", 1, true) and snapshot:find("pending yes (10.0s)", 1, true), snapshot)
    wield("slot_primary", melee, "action_wield")
    frame(0.6, "TASK")
    wield("slot_primary", melee)
    frame(5.4)
    assert(self:reserve_snapshot():find("last ranged sample", 1, true))
    wield("slot_secondary", template)
    frame(5.6, "AMMO LOW")
    frame(8.2)
    wield("slot_primary", melee)
    frame(8.4)
    wield("slot_secondary", template)
    frame(8.6) -- Swapping with the same low reserve does not retrigger.

    reset()
    slot.clips[1] = 1
    frame(0.2, "RELOAD")
    slot.reserve = 14
    frame(0.4, "RELOAD")
    wield("slot_primary", melee) -- Swap to melee right after the crossing.
    frame(0.6)
    frame(10.6)
    assert(self:reserve_snapshot():find("waiting for ranged weapon", 1, true))
    wield("slot_secondary", template)
    frame(10.8, "AMMO LOW") -- 0.6.1 let this expire while stowed; it now waits for the weapon.
    assert(self:reserve_snapshot():find("emitted", 1, true))
    frame(13.4)

    reset()
    settings.live_task_duration = 8
    device.interrupted = true
    frame(0.2, "TASK")
    slot.reserve = 10
    frame(0.4, "TASK")
    device.interrupted = false
    frame(7.8, "TASK")
    device.interrupted = true
    frame(8.0, "TASK") -- A second interruption keeps the weapon-out wait past ten seconds.
    frame(10.6, "TASK")
    assert(self:reserve_snapshot():find("expired while deferred", 1, true))
    device.interrupted = false
    frame(16.1)
    frame(16.3) -- Expired while the weapon was out: dropped, and the low baseline stays silent.
    settings.live_task_duration = 5

    reset()
    slot.reserve = 10
    frame(0.2, "AMMO LOW")
    slot.clips[1] = 1
    frame(0.4, "AMMO LOW")
    frame(1.0, "AMMO LOW")
    frame(1.3, "RELOAD")
    assert(self:reserve_snapshot():find("preempted by RELOAD", 1, true))
    frame(4, "AMMO LOW")
    frame(5.5) -- Cumulative visible time stays at the configured 2.5 seconds.

    reset()
    device.interrupted = true
    frame(0.2, "TASK")
    slot.clips[1] = 1
    frame(0.4, "TASK")
    frame(5.4, "RELOAD") -- A magazine crossing behind TASK survives.

    reset()
    slot.reserve = 10
    frame(0.2, "AMMO LOW")
    device.interrupted = true
    frame(0.4, "TASK") -- TASK ignores the one-second guard.
    slot.reserve = 20
    frame(0.6, "TASK") -- Pickup cancels a deferred resume.
    frame(5.6)
    slot.reserve = 10
    frame(5.8, "AMMO LOW") -- The pickup also rearmed the crossing.

    reset()
    slot.clips[1], slot.reserve = 1, 14
    frame(0.2, "RELOAD")
    wield("slot_primary", melee)
    frame(0.4)
    ranged_item = {}
    wield("slot_secondary", template)
    frame(0.6) -- Same template and slot, different item.
    slot.reserve = 20
    frame(0.8)
    slot.clips[1], slot.reserve = 3, 10
    frame(1.0, "AMMO LOW")
    unit = nil
    frame(1.2)
    unit = {}
    frame(1.4)
    live_hud:destroy()
    live_hud = setmetatable({}, {__index = hud_class})
    live_hud:init(parent, 0, 1)
    frame(0)
    reset()
    slot.reserve = 10
    frame(0.2, "AMMO LOW")
    toughness.remaining = 24
    slot.clips[1] = 1
    frame(0.4, "TOUGHNESS") -- Immediate interrupt of protected reserve; mag stays pending.
    wield("slot_primary", melee)
    frame(0.6, "TOUGHNESS") -- Toughness does not depend on the equipped weapon.
    wield("slot_secondary", template)
    frame(3.0, "RELOAD")
    frame(5.6, "AMMO LOW")
    unit = nil
    frame(5.8)
    unit = {}
    frame(6.0) -- Respawn low, with both categories silently baselined.
    toughness.remaining = 60
    frame(6.2)
    settings.live_broken = true
    toughness.remaining = 0
    frame(6.4, "BROKEN") -- A direct drop to zero produces only one label.
    frame(6.6, "BROKEN")
    live_hud:destroy()
    live_hud = setmetatable({}, {__index = hud_class})
    live_hud:init(parent, 0, 1)
    frame(0) -- New mission with zero toughness remains silent.
    settings.live_broken = false

    -- Double-barrelled shotgun: two-round capacity never shows RELOAD.
    slot.max_mag = 2
    reset()
    slot.clips[1], slot.reserve = 2, 40
    frame(0.2)
    wield("slot_secondary", template, "action_shoot")
    slot.clips[1] = 1
    frame(0.4)
    slot.clips[1] = 0
    frame(0.6)
    self.capture_echo = {}
    self.mag_command()
    assert(self.capture_echo[1]:find("capacity 2: LOW MAG off", 1, true), self.capture_echo[1])
    self.capture_echo = nil
    wield("slot_secondary", template, "action_reload_shell")
    slot.clips[1], slot.reserve = 2, 38
    frame(0.8)
    wield("slot_secondary", template, "action_shoot")
    slot.clips[1] = 1
    frame(1.0)
    slot.clips[1] = 0
    frame(1.2)
    slot.clips[1], slot.reserve = 2, 14 -- (Stub jump.) 16 of 102 total, just above 15%.
    frame(1.4)
    slot.clips[1] = 1
    frame(1.6, "AMMO LOW") -- Total supply still warns for two-round weapons.
    -- Five-round cylinder (Arbites shotpistol): RELOAD on the last round, as in 0.6.1.
    slot.max_mag = 5
    reset()
    slot.clips[1] = 2
    frame(0.2)
    slot.clips[1] = 1
    frame(0.4, "RELOAD")
    slot.max_mag = 10
    reset()

    -- Toughness through the real HUD path: extension from player_extensions().
    settings.toughness_diagnostics = true
    toughness.remaining = 100
    frame(0.2) -- Recovery above 50% rearms.
    toughness.remaining = 0
    frame(0.4, "TOUGHNESS") -- Healthy straight to zero with BROKEN off.
    toughness.remaining = 100
    frame(3.0)
    disabled.is_disabled = true
    toughness.remaining = 10
    frame(3.2) -- Netted: nothing drawn, but the baseline is kept.
    disabled.is_disabled = false
    frame(3.4, "TOUGHNESS") -- Reported on release instead of silently re-baselined.
    toughness.remaining = 100
    frame(6.0)
    device.interrupted = true
    frame(6.2, "TASK")
    toughness.remaining = 10
    frame(6.4, "TASK") -- TASK outranks toughness; the crossing is dropped, not queued.
    mod.capture_echo = {}
    mod.toughness_command()
    local snapshot, history = mod.capture_echo[1], mod.capture_echo[2]
    mod.capture_echo = nil
    assert(snapshot:find("10.0/100.0 (10.0%", 1, true) and snapshot:find("disarmed", 1, true)
        and snapshot:find("dropped TOUGHNESS: TASK visible", 1, true), snapshot)
    assert(history and history:find("crossed below threshold", 1, true), history)
    local saved_extension = toughness.max_toughness
    toughness.max_toughness = nil
    frame(6.6, "TASK")
    mod.capture_echo = {}
    mod.toughness_command()
    assert(mod.capture_echo[1]:find("invalid toughness values", 1, true), mod.capture_echo[1])
    mod.capture_echo = nil
    toughness.max_toughness = saved_extension
    settings.toughness_diagnostics = false

    live_hud:destroy()
    print("PASS: ammo arbitration timeline, stow-paused AMMO LOW, expiry, resume, pickups, identity, two- and five-round weapons and context resets")
end

function mod:test_ability_timeline(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local new_ability_extension = dofile("tests/ability_stub.lua")
    local combat = {name = "adamant_charge", charges = 1, max = 1, can_use = true}
    local grenade = {name = "veteran_frag_grenade", charges = 3, max = 3}
    local ability = new_ability_extension(combat, grenade)
    local toughness = {maximum = 100, remaining = 100,
        max_toughness = function(self) return self.maximum end,
        remaining_toughness = function(self) return self.remaining end}
    local unit, has_ability = {}, true
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function()
            return {unit = unit, unit_data = data, toughness = toughness, ability = has_ability and ability or nil}
        end,
    }
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    settings.live_task_duration, settings.live_low_mag_duration = 5, 2.5
    settings.ability_diagnostics = true
    local hud = setmetatable({}, {__index = hud_class})
    hud:init(parent, 0, 1)
    local function frame(t, expected)
        local previous = hud.draws or 0
        hud:draw(0, t)
        local actual = hud.draws ~= previous and hud._widgets_by_name.alert.content.message or nil
        assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
    end
    local function diagnostics()
        self.capture_echo = {}
        self.ability_command()
        local lines = self.capture_echo
        self.capture_echo = nil
        return lines[1], lines[2]
    end

    frame(0) -- Spawn with everything ready: silent.
    combat.charges = 0
    frame(0.2)
    combat.charges = 1
    frame(0.4, "ABILITY READY")
    assert(math.abs(hud._live.expires_at - 2.4) < 1e-9) -- Uses the shared ability duration (2 s).
    grenade.charges = 1
    frame(0.6, "ABILITY READY")
    grenade.charges = 2
    frame(0.8, "ABILITY READY") -- The grenade waits; it never interrupts.
    frame(2.5, "GRENADE +1")
    grenade.charges = 3
    frame(2.7, "GRENADE +2") -- A further gain merges into the visible notice.
    frame(4.6)

    -- Ammunition preempts a resource notice immediately.
    grenade.charges = 2
    frame(4.8)
    grenade.charges = 3
    frame(5.0, "GRENADE +1")
    slot.clips[1] = 1
    frame(5.2, "RELOAD")
    slot.clips[1] = 8
    frame(7.8)

    -- A readiness that waits behind TASK past its window is dropped, not queued forever.
    device.interrupted = true
    frame(8.0, "TASK")
    combat.charges = 0
    frame(8.2, "TASK")
    combat.charges = 1
    frame(8.4, "TASK")
    local snapshot = diagnostics()
    assert(snapshot:find("queued ABILITY READY", 1, true) and snapshot:find("pending ABILITY READY", 1, true), snapshot)
    frame(12.5, "TASK")
    frame(13.1)
    local _, history = diagnostics()
    assert(history:find("dropped ABILITY READY: expired behind higher alerts", 1, true), history)
    device.interrupted = false
    frame(13.2)

    -- Using the ability while its notice waits cancels the notice.
    toughness.remaining = 10
    frame(13.6, "TOUGHNESS")
    combat.charges = 0
    frame(13.8, "TOUGHNESS")
    combat.charges = 1
    frame(14.0, "TOUGHNESS")
    combat.charges = 0
    frame(14.2, "TOUGHNESS")
    assert(diagnostics():find("dropped ABILITY READY: ability no longer ready", 1, true))
    frame(16.2)
    toughness.remaining = 100

    -- Netted: nothing is drawn, the baseline survives, and the refill shows on release.
    disabled.is_disabled = true
    combat.charges = 1
    frame(16.4)
    disabled.is_disabled = false
    frame(16.6, "ABILITY READY")
    frame(18.7)

    -- Respawn: a new unit baselines silently whatever the counts are.
    unit = {}
    combat.charges, grenade.charges = 0, 1
    frame(18.8)
    combat.charges = 1
    frame(19.0, "ABILITY READY")
    frame(21.1)

    -- Arbites whistle: DOG READY from empty, with its own toggle.
    grenade.name, grenade.charges, grenade.max = "adamant_whistle", 2, 2
    frame(21.2) -- Changed blitz: silent baseline.
    grenade.charges = 0
    frame(21.4)
    grenade.charges = 1
    frame(21.6, "DOG READY")
    frame(23.7)
    settings.live_dog = false
    grenade.charges = 0
    frame(23.8)
    grenade.charges = 1
    frame(24.0)
    settings.live_dog = true

    -- No ability extension (or a game update removing it): no errors, no alerts.
    has_ability = false
    combat.charges = 0
    frame(24.2)
    assert(diagnostics():find("ability extension unavailable", 1, true))
    has_ability = true
    frame(24.4) -- Returning extension: same object, but nothing changed since its last good sample.

    hud:destroy()
    settings.ability_diagnostics = false
    print("PASS: ability and blitz HUD timeline: waiting, merging, preemption, expiry, cancellation, disable, respawn, dog and missing extension")
end

function mod:test_stimm_timeline(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local new_buffs = dofile("tests/stimm_stub.lua")
    local buffs = new_buffs()
    local templates = buffs.templates
    local toughness = {maximum = 100, remaining = 100,
        max_toughness = function(self) return self.maximum end,
        remaining_toughness = function(self) return self.remaining end}
    local unit = {}
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function()
            return {unit = unit, unit_data = data, toughness = toughness, buff = buffs}
        end,
    }
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    settings.live_task_duration, settings.live_low_mag_duration, settings.live_low_ammo_duration = 5, 2.5, 2.5
    assert(settings.live_stimm == true and settings.stimm_threshold == 3)
    local hud = setmetatable({}, {__index = hud_class})
    hud:init(parent, 0, 1)
    local function frame(t, expected, rgb)
        if type(buffs) == "table" and buffs.remove_finished then
            buffs.now = t
            buffs:remove_finished() -- Vanilla drops finished buffs on its own update.
        end
        local previous = hud.draws or 0
        hud:draw(0, t)
        local widget = hud._widgets_by_name.alert
        local actual = hud.draws ~= previous and widget.content.message or nil
        assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
        if actual then
            mod.check_symbols(hud, actual)
        end
        if rgb then
            assert(table.concat(widget.style.label.text_color, ",", 2, 4) == rgb and widget.content.marker == nil, t .. " colour")
        end
    end
    local function inject(t, kind, extra)
        buffs.now = t
        return buffs:add(templates[kind], extra)
    end

    frame(0)
    -- Hive Scum stimm: silent for the normal duration, one lime STIM 3s, gone when the effect ends.
    inject(0.5, "broker")
    frame(0.5)
    frame(5)
    frame(12.4) -- 3.1 seconds left.
    frame(12.5, "STIM 3s", "170,255,80")
    frame(14.4, "STIM 3s")
    frame(14.6) -- Two seconds on screen, no countdown.
    frame(15.6)

    -- Stimm Lab duration (20 s) behind TASK: the crossing waits, then is dropped when the effect ends.
    inject(20, "broker", 5)
    frame(20)
    device.interrupted = true
    frame(35, "TASK")
    frame(37, "TASK") -- 3 s left: crossing waits behind TASK.
    frame(39.9, "TASK")
    frame(40.1) -- TASK over and the stimm ended: no outdated STIM.
    device.interrupted = false
    frame(40.3)

    -- Toughness first; the delayed STIM shows the real remaining time and ends with the effect.
    inject(50, "broker")
    frame(50)
    toughness.remaining = 20
    frame(61, "TOUGHNESS")
    frame(62, "TOUGHNESS") -- Crossing waits behind toughness.
    frame(63.6, "STIM 2s", "170,255,80") -- 1.4 s left when it appears.
    frame(64.9, "STIM 2s")
    assert(hud._live.expires_at == 65 and hud._live.opacity < 1) -- Fades out with the effect, not after it.
    frame(65.1)
    toughness.remaining = 100
    frame(65.3)

    -- STIM interrupts a protected RELOAD at once.
    inject(70, "broker")
    frame(70)
    slot.clips[1] = 2
    frame(81.5, "RELOAD")
    frame(82, "STIM 3s")
    frame(84.1)
    slot.clips[1] = 8
    frame(84.3)

    -- Reinjection clears a showing STIM and starts a new cycle (picked-up power stimm).
    inject(90, "broker")
    frame(90)
    frame(102, "STIM 3s")
    inject(102.5, "power")
    frame(102.5)
    frame(114.4)
    frame(114.5, "STIM 3s")
    frame(116.6)

    -- Extension inside the threshold rearms: a second STIM only after it falls back to three seconds.
    local extended = inject(120, "broker")
    frame(120)
    frame(132, "STIM 3s")
    extended:add_duration(4)
    frame(133, "STIM 3s")
    assert(hud._live.started_at == 132)
    frame(134.1)
    frame(135.9)
    frame(136, "STIM 3s")
    frame(138.1)
    frame(139.1)

    -- A start-time correction around the threshold doesn't warn twice.
    local corrected = inject(140, "broker")
    frame(140)
    frame(152, "STIM 3s")
    corrected:set_start_time(140.6)
    frame(152.2, "STIM 3s")
    frame(152.6, "STIM 3s")
    assert(hud._live.started_at == 152)
    frame(154.1)
    frame(155.7)

    -- Toggle: off at the crossing stays silent; off while showing removes it.
    settings.live_stimm = false
    inject(160, "broker")
    frame(160)
    frame(172)
    settings.live_stimm = true
    frame(172.2)
    frame(175.1)
    inject(180, "broker")
    frame(180)
    frame(192, "STIM 3s")
    settings.live_stimm = false
    frame(192.2)
    settings.live_stimm = true
    frame(195.1)

    -- Netted at the crossing: reported on release while the effect still runs.
    inject(220, "broker")
    frame(220)
    frame(231)
    disabled.is_disabled = true
    frame(232)
    disabled.is_disabled = false
    frame(232.5, "STIM 3s") -- 2.5 s left, rounded up.
    frame(235.1)

    -- Death and respawn: a new unit and buff extension start empty and silent.
    inject(240, "broker")
    frame(240)
    unit = nil
    frame(250)
    unit, buffs = {}, new_buffs()
    templates = buffs.templates
    frame(252)
    frame(255.1)

    -- Mission transition: a new HUD joining inside the threshold stays silent.
    inject(260, "broker")
    frame(260)
    hud:destroy()
    hud = setmetatable({}, {__index = hud_class})
    hud:init(parent, 0, 1)
    frame(272.5)
    frame(275.1)

    -- Missing or broken buff extension: no alert and no error.
    buffs = nil
    frame(280)
    buffs = {buffs = function() error("unavailable") end}
    frame(280.2)
    hud:destroy()
    print("PASS: STIM HUD timeline: once per cycle, Stimm Lab, TASK/toughness precedence, no outdated STIM, ammo interrupt, reinjection, extension, correction, toggle, disable, respawn, mission and missing data")
end

-- 0.9.2 audit regressions (M1, M2, M3, M6) on the real HUD: stale waiting
-- notices are validated against the current state before they can show.
function mod:test_audit_regressions(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local new_ability_extension = dofile("tests/ability_stub.lua")
    local buffs = dofile("tests/stimm_stub.lua")()
    local combat = {name = "adamant_charge", charges = 1, max = 1, can_use = true}
    local grenade = {name = "veteran_frag_grenade", charges = 3, max = 3}
    local ability = new_ability_extension(combat, grenade)
    local toughness = {maximum = 100, remaining = 100,
        max_toughness = function(self) return self.maximum end,
        remaining_toughness = function(self) return self.remaining end}
    local unit, has_ability = {}, true
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function()
            return {unit = unit, unit_data = data, toughness = toughness, buff = buffs,
                ability = has_ability and ability or nil}
        end,
    }
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    settings.live_task_duration, settings.live_low_mag_duration = 2, 2.5
    settings.ability_diagnostics = true
    local hud = setmetatable({}, {__index = hud_class})
    hud:init(parent, 0, 1)
    local function frame(t, expected)
        buffs.now = t
        buffs:remove_finished()
        local previous = hud.draws or 0
        hud:draw(0, t)
        local actual = hud.draws ~= previous and hud._widgets_by_name.alert.content.message or nil
        assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
        if actual then
            mod.check_icons(hud, actual)
        end
    end
    local function task(t)
        device.interrupted = false
        frame(t - 0.1)
        device.interrupted = true
        frame(t, "TASK")
        device.interrupted = false -- TASK stays on screen for its two seconds.
    end
    local function decision()
        return hud._ability_state.decision
    end
    -- What is waiting: queued(nil) means nothing; held = true/false narrows to
    -- notices that can't / can be validated this sample.
    local function queued(key, held)
        local queue = hud._resource_queue or {}
        if key == nil then
            return #queue == 0
        end
        for _, notice in ipairs(queue) do
            if notice.key == key and (held == nil or (notice.held == true) == held) then
                return true
            end
        end
        return false
    end
    frame(0) -- Silent baselines.

    -- M1: GRENADE +1 waiting behind TASK is dropped once that charge is thrown.
    grenade.charges = 2
    frame(0.2)
    task(1)
    grenade.charges = 3
    frame(1.2, "TASK")
    assert(queued("live_blitz"))
    grenade.charges = 2
    frame(1.4, "TASK")
    assert(queued(nil) and decision() == "dropped GRENADE +1: charge spent")
    frame(3.1) -- Old code showed GRENADE +1 here.
    -- Two gained, one thrown while waiting: the notice shrinks to the charge still held.
    grenade.charges = 1
    frame(3.3)
    task(4)
    grenade.charges = 3
    frame(4.2, "TASK")
    grenade.charges = 2
    frame(4.4, "TASK")
    frame(6.1, "GRENADE +1")
    frame(8.2)

    -- M1: ABILITY READY waiting behind TASK is dropped once the ability is used again.
    combat.charges = 0
    frame(8.4)
    task(9)
    combat.charges = 1
    frame(9.2, "TASK")
    combat.charges = 0
    frame(9.4, "TASK")
    assert(decision() == "dropped ABILITY READY: ability no longer ready")
    frame(11.1)

    -- M1: a stale ABILITY READY no longer discards a newer valid GRENADE +1 in the same sample.
    task(12)
    combat.charges = 1
    frame(12.2, "TASK")
    combat.charges, grenade.charges = 0, 3 -- Ability used and a grenade regenerated together.
    frame(12.4, "TASK")
    assert(queued("live_blitz"))
    frame(14.1, "GRENADE +1")
    frame(16.2)

    -- M1: a missing extension or disabled slot is never proof of readiness. The
    -- notice waits (and still expires); it shows only once the slot reads ready again.
    task(17)
    combat.charges = 1
    frame(17.2, "TASK")
    has_ability = false
    frame(19.1) -- TASK over, extension missing: held, not shown.
    assert(queued("live_ability", true) and not queued("live_ability", false))
    has_ability = true
    frame(19.3, "ABILITY READY")
    frame(21.4)
    combat.charges = 0
    frame(21.6)
    task(22)
    combat.charges = 1
    frame(22.2, "TASK")
    combat.enabled = false -- Disabled (netted): kept baseline, unknown readiness.
    frame(24.1)
    combat.enabled, combat.charges = true, 0 -- Released, but the charge was spent meanwhile.
    frame(24.3)
    assert(queued(nil) and decision() == "dropped ABILITY READY: ability no longer ready")
    combat.charges = 1
    frame(24.5, "ABILITY READY") -- A genuine new readiness still alerts.
    frame(26.6)
    -- A held notice still expires on time.
    combat.charges = 0
    frame(26.8)
    task(27)
    combat.charges = 1
    frame(27.2, "TASK")
    has_ability = false
    frame(31.3)
    assert(queued(nil) and decision() == "dropped ABILITY READY: expired behind higher alerts")
    has_ability = true
    frame(31.5) -- Ready baseline kept, nothing new: silent.

    -- M6: an ordinary ammunition clip pickup no longer hides a regenerated grenade.
    local units = {}
    Unit = {alive = function(target) return units[target] ~= nil end,
        get_data = function(target) return units[target] end}
    local clip, crate = {}, {}
    units[clip], units[crate] = "small_clip", "ammo_cache_deployable"
    local ammo_hook = self.pickup_hooks[2].callback
    local talent_rules = {}
    ScriptUnit = {has_extension = function(target, system)
        return target == unit and system == "talent_system"
            and {has_special_rule = function(_, name) return talent_rules[name] end} or nil
    end}
    grenade.charges = 2
    frame(32)
    ammo_hook({}, nil, unit, {target_unit = clip}, 0, "success")
    frame(32.2)
    grenade.charges = 3
    frame(32.4, "GRENADE +1")
    frame(34.5)
    grenade.charges = 2
    frame(34.7)
    ammo_hook({}, nil, unit, {target_unit = crate}, 0, "success") -- A crate may refill grenades: still silent.
    frame(34.9)
    grenade.charges = 3
    frame(35.1)
    assert(decision() == "silent GRENADE +1: pickup")
    Unit, ScriptUnit = nil, nil

    -- M3: a RELOAD waiting behind TASK doesn't appear while the player is already reloading.
    frame(37.5)
    task(38)
    slot.clips[1] = 2
    frame(38.2, "TASK") -- Crossing waits behind TASK.
    action.current_action_name = "action_reload_shell"
    slot.clips[1], slot.reserve = 0, 82
    frame(38.4, "TASK")
    frame(40.1) -- TASK over: held while reloading (old code showed RELOAD).
    assert(hud._ammo_state.mag_decision == "held during reload")
    slot.clips[1], slot.reserve = 10, 72
    frame(40.5)
    action.current_action_name = "none"
    frame(40.7) -- The reload refilled the magazine: cancelled.
    assert(hud._ammo_state.mag_pending_until == nil and hud._ammo_state.mag_decision == "pending cancelled: magazine recovered")
    frame(41)
    -- An interrupted reload leaves the warning to show while it is still valid.
    slot.clips[1] = 8
    frame(41.2)
    task(42)
    slot.clips[1] = 2
    frame(42.2, "TASK")
    action.current_action_name = "action_reload_shell"
    frame(44.1)
    action.current_action_name = "none" -- Sprinting cancels the reload with two rounds left.
    frame(44.3, "RELOAD")
    frame(46.9)
    -- The normal RELOAD is unchanged: shown at the crossing.
    slot.clips[1] = 8
    frame(47)
    slot.clips[1] = 2
    frame(47.2, "RELOAD")
    action.current_action_name = "action_reload_shell" -- Reloading while it shows doesn't remove it.
    frame(47.4, "RELOAD")
    action.current_action_name = "none"
    slot.clips[1] = 8
    frame(49.8)

    -- M2: a STIM waiting behind TASK is dropped when the stimm is extended; only a new crossing warns.
    buffs.now = 50
    local stimm = buffs:add(buffs.templates.broker) -- 15 s: three seconds left at 62.
    frame(50)
    task(61.5)
    frame(62.2, "TASK")
    assert(hud._stimm_pending)
    stimm:add_duration(6) -- Nine seconds left: rearmed.
    frame(62.4, "TASK")
    assert(hud._stimm_pending == nil)
    frame(63.6) -- Old code showed STIM 9s here.
    frame(67.9)
    frame(68.1, "STIM 3s") -- The new crossing warns once.
    frame(70.2)
    frame(71.1)
    -- A STIM waiting behind TASK without an extension still shows its remaining time.
    buffs.now = 72
    buffs:add(buffs.templates.broker)
    frame(72)
    task(83.5)
    frame(84.1, "TASK")
    frame(85.6, "STIM 2s")
    frame(87.1)

    -- Ability diagnostics show a valid false as false, not nil.
    combat.can_use = false
    frame(87.3)
    self.capture_echo = {}
    self.ability_command()
    local line = self.capture_echo[1]
    self.capture_echo = nil
    assert(line:find("usable false", 1, true) and not line:find("usable nil", 1, true), line)
    combat.can_use = true
    frame(89)

    -- 0.9.3 M1: an ABILITY READY whose slot became unreadable is parked and can't
    -- make a fresh GRENADE +1 wait or be dropped. It rejoins once readable.
    local readable_charges = ability.remaining_ability_charges
    local function combat_unreadable(on)
        ability.remaining_ability_charges = on and function(ext, ability_type)
            if ability_type == "combat_ability" then
                error("unreadable")
            end
            return readable_charges(ext, ability_type)
        end or readable_charges
    end
    combat.charges, grenade.charges = 0, 2
    frame(89.2)
    task(90)
    combat.charges = 1
    frame(90.2, "TASK")
    assert(queued("live_ability", false))
    combat_unreadable(true)
    frame(90.4, "TASK")
    grenade.charges = 3
    frame(90.6, "TASK")
    assert(queued("live_blitz", false) and queued("live_ability", true))
    frame(92.1, "GRENADE +1") -- 0.9.2 dropped the grenade behind the unreadable notice.
    combat_unreadable(false)
    frame(93, "ABILITY READY") -- Readable, same ability, still ready: rejoins and outranks the grenade.
    frame(95.1)

    -- 0.9.3 M1: a notice for ability A never shows for a different ability B that is ready.
    combat.charges = 0
    frame(95.3)
    task(96)
    combat.charges = 1
    frame(96.2, "TASK")
    combat.name = "adamant_shout" -- Talent change: B equipped and already ready.
    frame(96.4, "TASK")
    assert(queued(nil) and decision() == "dropped ABILITY READY: ability changed")
    frame(98.1)
    -- The same change while the slot is unreadable: parked, then dropped once B reads.
    combat.charges = 0
    frame(98.3)
    task(99)
    combat.charges = 1
    frame(99.2, "TASK")
    has_ability = false
    frame(99.4, "TASK")
    combat.name = "adamant_charge"
    frame(101.1) -- Extension missing: nothing shown.
    assert(queued("live_ability", true))
    has_ability = true
    frame(101.3)
    assert(queued(nil) and decision() == "dropped ABILITY READY: ability changed")
    -- A replaced ability extension is a different identity too.
    combat.charges = 0
    frame(101.5)
    task(102)
    combat.charges = 1
    frame(102.2, "TASK")
    ability = new_ability_extension(combat, grenade)
    frame(102.4, "TASK")
    assert(queued(nil) and decision() == "dropped ABILITY READY: ability extension replaced")
    frame(104.1)

    -- 0.9.3 M6: Zealot Throwing Knives refill from ordinary clips (vanilla special
    -- rules disable_grenade_pickups + ammo_pickups_refills_grenades). That pickup's
    -- BLITZ +2 stays silent; a separate regeneration afterwards still notifies.
    local units = {}
    Unit = {alive = function(target) return units[target] ~= nil end,
        get_data = function(target) return units[target] end}
    local talent_rules = {disable_grenade_pickups = true, ammo_pickups_refills_grenades = true}
    ScriptUnit = {has_extension = function(target, system)
        return target == unit and system == "talent_system"
            and {has_special_rule = function(_, name) return talent_rules[name] end} or nil
    end}
    local clip = {}
    units[clip] = "small_clip"
    local ammo_hook = self.pickup_hooks[2].callback
    grenade.name, grenade.charges, grenade.max = "zealot_throwing_knives", 0, 12
    frame(104.3) -- New blitz: silent baseline.
    ammo_hook({}, nil, unit, {target_unit = clip}, 0, "success")
    frame(104.5)
    grenade.charges = 2 -- Restored by the clip.
    frame(104.7)
    assert(decision() == "silent BLITZ +2: pickup")
    grenade.charges = 0
    frame(104.9)
    grenade.charges = 1 -- Melee-kill regeneration inside the same two seconds.
    frame(105.1, "BLITZ +1") -- The pickup already explained its one gain.
    frame(107.2)
    -- Without the talents the same clip explains nothing: BLITZ +2 is regeneration.
    talent_rules = {}
    grenade.charges = 0
    frame(107.4)
    ammo_hook({}, nil, unit, {target_unit = clip}, 0, "success")
    frame(107.6)
    grenade.charges = 2
    frame(107.8, "BLITZ +2")
    frame(110)
    Unit, ScriptUnit = nil, nil
    grenade.name, grenade.charges, grenade.max = "veteran_frag_grenade", 3, 3
    frame(110.2)

    -- 0.9.3 M2: a short genuine extension (Buff.add_duration) that lifts a waiting
    -- STIM out of the warning window drops it; the fresh crossing warns once.
    buffs.now = 111
    local short = buffs:add(buffs.templates.broker) -- Ends at 126.
    frame(111)
    task(121.5) -- TASK until 123.5.
    frame(123.1, "TASK") -- 2.9 s left: crossing waits.
    assert(hud._stimm_pending)
    short:add_duration(0.8) -- 2.7 -> 3.5 s left at 123.3.
    frame(123.3, "TASK")
    assert(hud._stimm_pending == nil and hud._stimm_state.armed)
    frame(123.6) -- 0.9.2 showed STIM 4s here.
    frame(123.9, "STIM 3s") -- Fresh crossing (2.9 s left): one warning.
    frame(125.8, "STIM 3s")
    frame(126)
    frame(127)

    hud:destroy()
    settings.ability_diagnostics, settings.live_task_duration = false, 5
    print("PASS: 0.9.2 audit regressions: stale GRENADE +1 / ABILITY READY dropped, newer event kept, missing extension held and expiring, clip pickups (M6), RELOAD held during reload, STIM dropped after extension, diagnostics keep false; 0.9.3: unreadable notice parked, ability identity, Throwing Knives clip refill, short STIM extension")
end

-- 0.9.4 queue and pickup-accounting regressions. Each scenario runs on its own
-- HUD and asserts only what the player sees; failures are collected so one run
-- lists every scenario that misbehaves.
function mod:test_queue_accounting(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local new_ability_extension = dofile("tests/ability_stub.lua")
    local ammo_hook = self.pickup_hooks[2].callback
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    local function env(combat, grenade)
        local e = {combat = combat, grenade = grenade, unit = {}, present = true, unreadable = {}, rules = {}}
        local function new_extension()
            local ext = new_ability_extension(combat, grenade)
            local charges = ext.remaining_ability_charges
            function ext:remaining_ability_charges(ability_type)
                if e.unreadable[ability_type] then
                    error("unreadable")
                end
                return charges(self, ability_type)
            end
            return ext
        end
        e.ability = new_extension()
        e.new_extension = new_extension
        local toughness = {maximum = 100, remaining = 100,
            max_toughness = function(t) return t.maximum end,
            remaining_toughness = function(t) return t.remaining end}
        local data = {read_component = function(_, key)
            return ammo_components[key] or assert(components[key])
        end}
        e.parent = {
            player_unit = function() return e.unit end,
            player_extensions = function()
                return {unit = e.unit, unit_data = data, toughness = toughness,
                    ability = e.present and e.ability or nil}
            end,
        }
        inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
        action.template, action.current_action_name = template, "none"
        slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
        map.a, device.interrupted = device, false
        e.hud = setmetatable({}, {__index = hud_class})
        e.hud:init(e.parent, 0, 1)
        local pickups = {}
        Unit = {alive = function(target) return pickups[target] ~= nil end,
            get_data = function(target) return pickups[target] end}
        ScriptUnit = {has_extension = function(target, system)
            return target == e.unit and system == "talent_system"
                and {has_special_rule = function(_, name) return e.rules[name] end} or nil
        end}
        function e.pickup(kind)
            local target = {}
            pickups[target] = kind
            ammo_hook({}, nil, e.unit, {target_unit = target}, 0, "success")
        end
        function e.frame(t, expected)
            local previous = e.hud.draws or 0
            e.hud:draw(0, t)
            local actual = e.hud.draws ~= previous and e.hud._widgets_by_name.alert.content.message or nil
            assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
        end
        function e.task(t)
            device.interrupted = false
            e.frame(t - 0.1)
            device.interrupted = true
            e.frame(t, "TASK")
            device.interrupted = false
        end
        return e
    end
    local frag = function(charges) return {name = "veteran_frag_grenade", charges = charges, max = 3} end
    local knives = function(charges) return {name = "zealot_throwing_knives", charges = charges, max = 12} end
    local ready = function(charges) return {name = "adamant_charge", charges = charges, max = 1, can_use = true} end

    local scenarios = {
        {"M1: an unvalidated ABILITY READY never evicts a valid waiting GRENADE +1", function()
            local e = env(ready(0), frag(2))
            e.frame(0)
            e.task(1)
            e.combat.charges = 1
            e.frame(1.2, "TASK") -- ABILITY READY waits.
            e.unreadable.combat_ability = true
            e.frame(1.4, "TASK")
            e.grenade.charges = 3
            e.frame(1.6, "TASK") -- GRENADE +1 waits.
            e.present = false -- The whole extension disappears for a sample.
            e.frame(1.8, "TASK")
            e.present, e.unreadable.combat_ability, e.combat.charges = true, nil, 0 -- Back, ability spent.
            e.frame(2.0, "TASK")
            e.frame(3.1, "GRENADE +1")
            e.frame(5.2)
        end},
        {"M1: a lower notice that can't be validated is kept, then shows once valid", function()
            local e = env(ready(0), frag(2))
            e.frame(0)
            e.task(1)
            e.grenade.charges = 3
            e.frame(1.2, "TASK") -- GRENADE +1 waits.
            e.unreadable.grenade_ability = true
            e.frame(1.4, "TASK")
            e.combat.charges = 1
            e.frame(1.6, "TASK") -- ABILITY READY outranks it, but can't drop an unvalidated notice...
            e.combat.charges = 0
            e.frame(1.8, "TASK") -- ...and is itself cancelled.
            e.unreadable.grenade_ability = nil
            e.frame(2.0, "TASK")
            e.frame(3.1, "GRENADE +1")
        end},
        {"M1: a returning GRENADE +1 merges with a newer gain into GRENADE +2 with a refreshed deadline", function()
            settings.live_task_duration = 4.3 -- TASK covers 1.0 to 5.3.
            local e = env(ready(1), frag(1))
            e.frame(0)
            e.task(1)
            e.grenade.charges = 2
            e.frame(1.2, "TASK") -- GRENADE +1 waits until 5.2.
            e.unreadable.grenade_ability = true
            e.frame(1.4, "TASK")
            e.unreadable.grenade_ability, e.grenade.charges = nil, 3
            e.frame(1.6, "TASK") -- Second charge: one notice, deadline 5.6.
            e.frame(5.4, "GRENADE +2")
            e.frame(7.5) -- No duplicate.
        end},
        {"M1: a returning ABILITY READY outranks a newer GRENADE; a returning GRENADE yields to a newer ABILITY READY", function()
            local e = env(ready(0), frag(2))
            e.frame(0)
            e.task(1)
            e.combat.charges = 1
            e.frame(1.2, "TASK")
            e.unreadable.combat_ability = true
            e.frame(1.4, "TASK")
            e.grenade.charges = 3
            e.frame(1.6, "TASK")
            e.unreadable.combat_ability = nil
            e.frame(1.8, "TASK") -- Same ability, still ready: it rejoins above the grenade.
            e.frame(3.1, "ABILITY READY")
            e.frame(5.2) -- The single-slot rule still drops the lower notice.
            e.combat.charges, e.grenade.charges = 0, 2
            e.frame(5.4)
            e.task(6)
            e.grenade.charges = 3
            e.frame(6.2, "TASK")
            e.unreadable.grenade_ability = true
            e.frame(6.4, "TASK")
            e.combat.charges = 1
            e.frame(6.6, "TASK")
            e.unreadable.grenade_ability = nil
            e.frame(6.8, "TASK")
            e.frame(8.1, "ABILITY READY")
            e.frame(10.2)
        end},
        {"M1: a notice that stays unreadable expires on time and never shows later", function()
            local e = env(ready(0), frag(3))
            e.frame(0)
            e.task(1)
            e.combat.charges = 1
            e.frame(1.2, "TASK")
            e.unreadable.combat_ability = true
            e.frame(3.1)
            e.frame(5.3) -- Past its four seconds while unreadable.
            e.unreadable.combat_ability = nil
            e.frame(5.5) -- Readable, same ability, still ready: expired all the same.
            e.frame(7)
        end},
        {"M1: partial expenditure while waiting and unreadable", function()
            local e = env(ready(1), frag(0))
            e.frame(0)
            e.task(1)
            e.grenade.charges = 1
            e.frame(1.2, "TASK")
            e.grenade.charges = 2
            e.frame(1.4, "TASK") -- GRENADE +2.
            e.unreadable.grenade_ability = true
            e.frame(1.6, "TASK")
            e.unreadable.grenade_ability, e.grenade.charges = nil, 1 -- One thrown meanwhile.
            e.frame(1.8, "TASK")
            e.frame(3.1, "GRENADE +1")
            e.frame(5.2)
        end},
        {"M6: each pickup credit expires on its own (A 0.2, B 2.0, refill 2.4, regeneration 2.6)", function()
            local e = env(ready(1), frag(1))
            e.frame(0)
            e.pickup("ammo_cache_deployable")
            e.frame(0.2)
            e.frame(1.0)
            e.pickup("ammo_cache_deployable")
            e.frame(2.0)
            e.grenade.charges = 2
            e.frame(2.4) -- B's refill.
            e.grenade.charges = 3
            e.frame(2.6, "GRENADE +1") -- A expired at 2.2: independent regeneration.
        end},
        {"M6: overlapping credits are consumed oldest first and expire independently", function()
            local e = env(ready(1), frag(0))
            e.frame(0)
            e.pickup("ammo_cache_deployable")
            e.frame(0.2)
            e.pickup("ammo_cache_deployable")
            e.frame(1.0)
            e.grenade.charges = 1
            e.frame(1.5) -- A's refill.
            e.grenade.charges = 2
            e.frame(2.5) -- B's refill (A would have expired; B lasts to 3.0).
            e.grenade.charges = 3
            e.frame(2.7, "GRENADE +1") -- No credit left.
        end},
        {"M6: an unused credit expires normally", function()
            local e = env(ready(1), frag(1))
            e.frame(0)
            e.pickup("ammo_cache_deployable")
            e.frame(0.2)
            e.grenade.charges = 2
            e.frame(2.5, "GRENADE +1")
        end},
        {"M6: a refill that earns no notice still uses its credit (Throwing Knives 1 -> 3, then 0 -> 1)", function()
            local e = env(ready(1), knives(1))
            e.rules.disable_grenade_pickups, e.rules.ammo_pickups_refills_grenades = true, true
            e.frame(0)
            e.pickup("small_clip")
            e.frame(0.2)
            e.grenade.charges = 3
            e.frame(0.4) -- Not from empty: no notice, but this is the clip's refill.
            e.grenade.charges = 0
            e.frame(0.6)
            e.grenade.charges = 1
            e.frame(0.8, "BLITZ +1") -- Melee-kill regeneration.
            e.frame(2.9)
            -- The pool rules are unchanged: a regeneration above zero stays silent.
            e.grenade.charges = 2
            e.frame(3.1)
        end},
        {"M6: a refill while the blitz toggle is off still uses its credit", function()
            local e = env(ready(1), frag(1))
            e.frame(0)
            settings.live_blitz = false
            e.pickup("ammo_cache_deployable")
            e.frame(0.2)
            e.grenade.charges = 2
            e.frame(0.4)
            settings.live_blitz = true
            e.grenade.charges = 3
            e.frame(0.6, "GRENADE +1")
        end},
        {"HUD recreation and a new player unit clear waiting notices and pickup credits", function()
            local e = env(ready(0), frag(2))
            e.frame(0)
            e.task(1)
            e.combat.charges = 1
            e.frame(1.2, "TASK")
            e.pickup("ammo_cache_deployable")
            e.frame(1.4, "TASK")
            e.hud:destroy()
            e.hud = setmetatable({}, {__index = hud_class}) -- Mission change.
            e.hud:init(e.parent, 0, 1)
            e.frame(1.6) -- Fresh baselines: nothing carried over.
            e.frame(3.1)
            e.grenade.charges = 3
            e.frame(3.3, "GRENADE +1") -- The old HUD's credit is gone.
            e.frame(5.4)
            e.combat.charges, e.grenade.charges = 0, 2
            e.frame(5.6)
            e.task(6)
            e.combat.charges = 1
            e.frame(6.2, "TASK")
            e.pickup("ammo_cache_deployable")
            e.frame(6.4, "TASK")
            e.unit = {} -- Respawn: a new unit resets live state.
            e.frame(6.6)
            e.frame(8.1)
            e.grenade.charges = 3
            e.frame(8.3, "GRENADE +1")
        end},
    }
    local failed = {}
    for _, scenario in ipairs(scenarios) do
        settings.live_task_duration, settings.live_blitz = 2, true
        local ok, err = pcall(scenario[2])
        if not ok then
            failed[#failed + 1] = scenario[1] .. "\n      " .. tostring(err)
        end
    end
    Unit, ScriptUnit = nil, nil
    settings.live_task_duration, settings.live_blitz = 5, true
    device.interrupted = false
    assert(#failed == 0, #failed .. " queue/pickup scenario(s) failed:\n    " .. table.concat(failed, "\n    "))
    print("PASS: 0.9.4 queue and pickup accounting: unvalidated notices never evict, merge on return, rejoin by priority, expire while unreadable, partial spend; independent FIFO credits, expiry, consumption without a notice, toggle off, HUD and unit resets")
end

function mod:set_setting(key, value) settings[key] = value end

-- Approved artwork: nine alerts, each with a 64 px and a 128 px RGBA PNG at the
-- path Simple Assets is given (mods/DarktideCrosshairAlerts/...).
do
    local Icons = dofile("DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/icon_textures.lua")
    local expected = {live_task = "objective", live_low_mag = "magazine", live_low_ammo = "low-ammunition",
        live_toughness = "shield", live_broken = "broken-shield", live_ability = "ability-ready",
        live_blitz = "grenade", live_dog = "dog-command", live_stimm = "stimulant"}
    local count = 0
    for key, file in pairs(Icons.files) do
        count = count + 1
        assert(expected[key] == file, key)
        for _, size in ipairs({64, 128}) do
            local path = Icons.path(size, key)
            assert(path == ("mods/DarktideCrosshairAlerts/assets/icons/%d/%s.png"):format(size, file))
            local header = assert(mod.png_header(path:gsub("^mods/", "")), path)
            assert(header.signature == "\137PNG\r\n\26\n" and header.width == size and header.height == size
                and header.colour_type == 6, path .. " is a transparent RGBA PNG at its size")
        end
    end
    assert(count == 9 and #Icons.sizes == 2)
    print("PASS: icon asset mapping: nine approved icons, 64 and 128 px RGBA PNGs at the expected mod paths")
end


function mod:test_icon_modes(device, map, ammo_components, slot, template)
    local unit = {}
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function() return {unit = unit, unit_data = data} end,
    }
    local function new_hud()
        local hud = setmetatable({}, {__index = dofile(self.hud.filename .. ".lua")})
        hud:init(parent, 0, 1)
        hud:draw(0, -1) -- First sight of the unit resets live state.
        return hud
    end
    local alerts = {
        {"live_task", "TASK"}, {"live_low_mag", "RELOAD"}, {"live_low_ammo", "AMMO LOW"},
        {"live_toughness", "TOUGHNESS"}, {"live_broken", "BROKEN"}, {"live_ability", "ABILITY READY"},
        {"live_blitz", "GRENADE +1"}, {"live_blitz", "BLITZ +2"}, {"live_dog", "DOG READY"}, {"live_stimm", "STIM 3s"},
    }
    local palette = {live_task = "240,110,160", live_low_mag = "255,200,61", live_low_ammo = "255,77,77",
        live_toughness = "77,210,255", live_broken = "255,77,77", live_ability = "255,214,40",
        live_blitz = "215,215,215", live_dog = "200,168,255", live_stimm = "170,255,80"}
    settings.alert_color = {255, 240, 110, 160}
    settings.preview, settings.live_broken = true, true -- BROKEN is off by default.
    local function show(hud, key, message, t, ui_renderer)
        -- Ammo alerts belong to the equipped weapon, as when they are raised live.
        hud._live = {key = key, message = message, slot = "slot_secondary", template = template, started_at = t}
        local previous = hud.draws or 0
        hud:draw(0, t, ui_renderer)
        assert(hud.draws == previous + 1, message)
        self.check_icons(hud, message, ui_renderer and ui_renderer.scale)
        return hud._widgets_by_name.alert
    end
    local function all_modes(label)
        for _, mode in ipairs({"text", "icon", "icon_text"}) do
            settings.alert_display = mode
            local hud = new_hud()
            for i, alert in ipairs(alerts) do
                local widget = show(hud, alert[1], alert[2], i * 10)
                assert(table.concat(widget.style.label.text_color, ",", 2, 4) == palette[alert[1]], alert[2])
                assert(widget.content.marker == nil and widget.style.marker == nil, alert[2] .. " has no underline")
                hud._live = nil
            end
            self.preview() -- Previews have no category: text in every mode.
            local widget = show(hud, nil, "TEST ALERT", 200)
            assert(widget.content.icon_texture == nil and hud.rendered.label, label)
            hud:clear_preview()
            hud:destroy()
        end
    end

    -- Without Simple Assets: every mode stays a working text alert.
    local icons = self.reset_icons(nil)
    all_modes("no dependency")
    assert(icons.state.status == "unavailable")

    -- Simple Assets installed later: the next HUD retries; while loading, text.
    local simple_assets = self.new_simple_assets()
    self.set_external_mod("SimpleAssets", simple_assets)
    settings.alert_display = "icon"
    local hud = new_hud()
    assert(icons.state.status == "loading" and simple_assets.files == 18)
    for _, path in ipairs(simple_assets.paths) do
        assert(path:find("^mods/DarktideCrosshairAlerts/assets/icons/") and path:find("%.png$"))
    end
    local widget = show(hud, "live_dog", "DOG READY", 0)
    assert(widget.content.icon_texture == nil and hud.rendered.label)
    hud:destroy()
    new_hud():destroy() -- Mission transition while loading: no second request.
    assert(simple_assets.files == 18)
    simple_assets.settle()
    assert(icons.state.status == "ready" and icons.state.loaded == 18 and #icons.state.missing == 0)

    -- Loaded: every category in every mode, then reuse across HUDs and frames.
    all_modes("ready")
    local first = icons.texture("live_low_mag", 28)
    for _ = 1, 3 do
        hud = new_hud() -- Each mission builds a new HUD.
        for t = 1, 50 do
            hud:draw(0, t / 10)
        end
        hud:destroy()
    end
    assert(simple_assets.files == 18 and icons.texture("live_low_mag", 28) == first)
    assert(self.request_icons() == "ready" and simple_assets.files == 18)

    -- Scaling: the icon follows the pop size and picks the 128 px export when drawn above 64 pixels.
    settings.alert_display = "icon"
    hud = new_hud()
    widget = show(hud, "live_low_mag", "RELOAD", 0)
    assert(widget.style.label.font_size == 29 and math.abs(widget.style.icon.size[1] - 28 * 29 / 23) < 1e-9)
    assert(widget.style.icon.material_values.texture_map.path:find("/64/magazine.png", 1, true))
    hud:draw(0, 1)
    assert(widget.style.icon.size[1] == 28 and widget.style.icon_outline_1.size[2] == 28)
    widget = show(hud, "live_task", "TASK", 2)
    assert(widget.style.label.font_size == 33 and math.abs(widget.style.icon.size[1] - 28 * 33 / 23) < 1e-9)
    package.loaded["scripts/managers/ui/ui_renderer"] = {text_size = function() return 90 end}
    widget = show(hud, "live_stimm", "STIM 3s", 4, {scale = 2}) -- 4K-like render scale.
    assert(widget.style.icon.material_values.texture_map.path:find("/128/stimulant.png", 1, true))
    package.loaded["scripts/managers/ui/ui_renderer"] = nil
    hud:destroy()

    -- Category colours off: the icon takes the saved Notification colour, like the text.
    settings.category_colors = false
    hud = new_hud()
    widget = show(hud, "live_dog", "DOG READY", 0)
    assert(table.concat(widget.style.icon.color, ",", 2, 4) == "240,110,160")
    hud:destroy()
    settings.category_colors = true

    -- Text only never assigns a texture, even when loaded.
    settings.alert_display = "text"
    hud = new_hud()
    widget = show(hud, "live_toughness", "TOUGHNESS", 0)
    assert(widget.style.icon.material_values.texture_map == nil and not hud.rendered.icon)
    hud:destroy()

    -- An unknown saved value behaves as the default, Icon + text.
    settings.alert_display = "sideways"
    hud = new_hud()
    widget = show(hud, "live_stimm", "STIM 3s", 0)
    settings.alert_display = "icon_text"
    assert(widget.content.icon_texture and hud.rendered.label and hud.rendered.icon)
    hud:destroy()

    -- Vanilla text measurement places the icon against the measured width.
    package.loaded["scripts/managers/ui/ui_renderer"] = {text_size = function(_, text, font, size)
        assert(text == "RELOAD" and font == "proxima_nova_bold" and size == 29)
        return 100, size
    end}
    hud = new_hud()
    hud.measured_width = 100
    widget = show(hud, "live_low_mag", "RELOAD", 0, {scale = 1})
    local total = 28 * 29 / 23 + 8 * 29 / 23 + 100
    assert(math.abs(widget.style.label.offset[1] - (total / 2 - 50)) < 1e-9)
    package.loaded["scripts/managers/ui/ui_renderer"] = {text_size = function() error("no font") end}
    hud:destroy()
    hud = new_hud()
    show(hud, "live_low_mag", "RELOAD", 0, {scale = 1}) -- Measurement failure uses the estimate.
    hud:destroy()
    package.loaded["scripts/managers/ui/ui_renderer"] = nil

    -- One missing file: that alert uses the other export; both missing: text.
    simple_assets = self.new_simple_assets()
    icons = self.reset_icons(simple_assets)
    self.request_icons()
    simple_assets.settle({[icons.path(64, "live_dog")] = true})
    settings.alert_display = "icon"
    hud = new_hud()
    widget = show(hud, "live_dog", "DOG READY", 0)
    assert(widget.style.icon.material_values.texture_map.path:find("/128/dog-command.png", 1, true))
    icons = self.reset_icons(self.new_simple_assets())
    self.request_icons()
    external_mods.SimpleAssets.settle({[icons.path(64, "live_dog")] = true, [icons.path(128, "live_dog")] = true})
    assert(icons.state.status == "ready" and #icons.state.missing == 2)
    widget = show(hud, "live_dog", "DOG READY", 10)
    assert(widget.content.icon_texture == nil and hud.rendered.label and not hud.rendered.icon)
    show(hud, "live_ability", "ABILITY READY", 20)
    assert(hud.rendered.icon and not hud.rendered.label)
    hud:destroy()

    -- Simple Assets failing: an error, a rejected promise or no textures at all all mean text.
    for _, failure in ipairs({"throw", "reject", "none"}) do
        simple_assets = self.new_simple_assets({throw = failure == "throw" and "runtime missing" or nil})
        icons = self.reset_icons(simple_assets)
        self.request_icons()
        if failure == "reject" then
            simple_assets.reject({is_ok = false, error = "denied"})
        elseif failure == "none" then
            local everything = {}
            for _, path in ipairs(simple_assets.paths) do
                everything[path] = true
            end
            simple_assets.settle(everything)
        end
        assert(icons.state.status == "failed" and icons.state.reason, failure)
        hud = new_hud()
        show(hud, "live_task", "TASK", 0)
        assert(hud.rendered.label and not hud.rendered.icon and simple_assets.files == 18, failure)
        hud:destroy()
    end
    assert(simple_assets.files == 18) -- A failed load is not retried every HUD.
    self.set_external_mod("SimpleAssets", {}) -- Present but without the API: unavailable.
    icons = self.reset_icons({})
    assert(self.request_icons() == "unavailable")

    self.reset_icons(self.new_simple_assets(), true) -- Leave icons loaded for later timelines.
    settings.alert_color, settings.preview, settings.alert_display, settings.live_broken = nil, false, "icon_text", false
    print("PASS: approved icons: dependency missing, late, loading, failing and partial; one load reused across HUDs and frames; every category in all three modes; tint, outline, scaling, 128 px at high resolution, centring and measured layout")
end

-- Model of vanilla UrlLoaderManager (scripts/managers/url_loader/url_loader_manager.lua),
-- checked against that file: every load_texture call takes a reference, even for a
-- cached or in-flight URL; a failure is cached like a success and returned rejected
-- until the URL's count reaches 0; unload_texture on an unheld URL raises; a texture
-- is destroyed when its count reaches 0. Backend requests stay in flight until the
-- test completes them, so completion can be ordered against HUD frames and unloads.
function mod.new_url_loader()
    local loader = {refs = {}, cached = {}, pending = {}, requests = {}, fail = {}, hold = {}, textures = {}, bad_unloads = 0}
    function loader:load_texture(url)
        self.refs[url] = (self.refs[url] or 0) + 1
        if self.pending[url] then
            return self.pending[url]
        end
        local data = self.cached[url]
        if data then
            local promise = Deferred.new()
            if data.is_ok then promise:resolve(data) else promise:reject(data) end
            return promise
        end
        self.requests[url] = (self.requests[url] or 0) + 1
        self.pending[url] = Deferred.new()
        return self.pending[url]
    end
    function loader:destroy_data(url)
        local data = self.cached[url]
        self.cached[url], self.refs[url] = nil, nil
        if data.texture then
            data.texture.released = true
        end
    end
    function loader:unload_texture(url)
        if self.refs[url] == nil then
            self.bad_unloads = self.bad_unloads + 1
        end
        local count = self.refs[url] - 1 -- Raises for an unheld URL, as vanilla does.
        self.refs[url] = count
        if count == 0 and self.cached[url] ~= nil then
            self:destroy_data(url)
        end
    end
    function loader:update()
        for url, count in pairs(self.refs) do
            if count == 0 and not self.pending[url] then
                self:destroy_data(url)
            end
        end
    end
    -- Completes every in-flight request; fail[url] = n fails the next n, true always.
    function loader:complete()
        local urls = {}
        for url in pairs(self.pending) do
            if not self.hold[url] then urls[#urls + 1] = url end
        end
        table.sort(urls)
        for _, url in ipairs(urls) do
            local promise, failing = self.pending[url], self.fail[url]
            self.pending[url] = nil
            if failing then
                if failing ~= true then
                    self.fail[url] = failing > 1 and failing - 1 or nil
                end
                self.cached[url] = {is_ok = false, url = url}
                promise:reject(self.cached[url])
            else
                local texture = {path = url:gsub("^simpleassets://", ""), url = url}
                self.textures[#self.textures + 1] = texture
                self.cached[url] = {is_ok = true, url = url, texture = texture, width = 64, height = 64}
                promise:resolve(self.cached[url])
            end
        end
        self:update()
    end
    function loader:held(url)
        return self.refs[url] or 0
    end
    return loader
end

-- Simple Assets 2.0.1 load_textures over that loader: an image goes to
-- Managers.url_loader:load_texture with its simpleassets:// URL; a file it can't
-- read is rejected without a URL or a reference; item failures land in the
-- result map and the outer promise resolves once every item has settled.
function mod.new_loader_simple_assets()
    -- files and requested[path] count requests however they are grouped. raise[path]:
    -- "before" raises while inspecting the file (no reference taken, as a header read
    -- error would); "after" raises once vanilla has counted the reference.
    local simple_assets = {files = 0, requested = {}, unreadable = {}, raise = {}}
    function simple_assets.load_textures(paths)
        local results, remaining, outer = {}, #paths, Deferred.new()
        local function settled()
            remaining = remaining - 1
            if remaining == 0 then outer:resolve(results) end
        end
        for _, path in ipairs(paths) do
            simple_assets.files = simple_assets.files + 1
            simple_assets.requested[path] = (simple_assets.requested[path] or 0) + 1
            local raise = simple_assets.raise[path]
            simple_assets.raise[path] = nil
            if raise == "before" then error("header read raised for " .. path) end
            if raise == "after" then
                Managers.url_loader:load_texture("simpleassets://" .. path, false)
                error("backend raised for " .. path)
            end
            local unreadable = simple_assets.unreadable[path]
            if unreadable or not png_header(path:gsub("^mods/", "")) then
                if unreadable and unreadable ~= true then
                    simple_assets.unreadable[path] = unreadable > 1 and unreadable - 1 or nil
                end
                results[path] = {is_ok = false, error = "read failed"}
                settled()
            else
                Managers.url_loader:load_texture("simpleassets://" .. path, false):next(function(value)
                    results[path] = value
                    settled()
                end, function(failure)
                    results[path] = failure
                    settled()
                end)
            end
        end
        return outer
    end
    return simple_assets
end

-- M4/M5: texture retry and URL-loader ownership, through the HUD, the mod's
-- unload event and the vanilla loader model.
function mod:test_texture_lifecycle(device, map, ammo_components, slot, template)
    local unit = {}
    local data = {read_component = function(_, key) return ammo_components[key] or assert(components[key]) end}
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function() return {unit = unit, unit_data = data} end,
    }
    settings.preview, settings.live_broken = true, true
    local saved_managers = Managers
    local alerts = {
        {"live_task", "TASK"}, {"live_low_mag", "RELOAD"}, {"live_low_ammo", "AMMO LOW"},
        {"live_toughness", "TOUGHNESS"}, {"live_broken", "BROKEN"}, {"live_ability", "ABILITY READY"},
        {"live_blitz", "GRENADE +1"}, {"live_dog", "DOG READY"}, {"live_stimm", "STIM 3s"},
    }
    local loader, simple_assets, icons, hud
    local function new_hud(t)
        local created = setmetatable({}, {__index = dofile(self.hud.filename .. ".lua")})
        created:init(parent, 0, 1)
        created:draw(0, t or -1)
        return created
    end
    -- One alert frame: rendered exactly as check_icons expects, never with a released texture.
    local function show(key, message, t)
        hud._live = {key = key, message = message, slot = "slot_secondary", template = template, started_at = t}
        hud:draw(0, t)
        self.check_icons(hud, message)
        local drawn = hud._widgets_by_name.alert.style.icon.material_values.texture_map
        assert(not (drawn and drawn.released), message .. " drawn with a released texture")
        hud._live = nil
        return hud._widgets_by_name.alert.content.icon_texture
    end
    local function frames(from, to)
        for t = from, to do hud:draw(0, t) end
    end
    local function url(key, size) return "simpleassets://" .. icons.path(size or 64, key) end
    local function all_urls()
        local list = {}
        for _, size in ipairs({64, 128}) do
            for _, alert in ipairs(alerts) do list[#list + 1] = url(alert[1], size) end
        end
        return list
    end
    -- A fresh load of the mod: DMF runs main.lua again, and with it a new icon module.
    local function load_mod(fresh_loader, before_request)
        if fresh_loader then
            loader = self.new_url_loader()
            Managers = setmetatable({url_loader = loader}, {__index = saved_managers})
        end
        simple_assets = self.new_loader_simple_assets()
        icons = self.reset_icons(simple_assets)
        if before_request then before_request() end
        self.on_all_mods_loaded()
    end
    local function each_mode(check)
        for _, mode in ipairs({"text", "icon", "icon_text"}) do
            settings.alert_display = mode
            check(mode)
        end
        settings.alert_display = "icon_text"
    end
    local function refs_each(expected, label)
        for _, u in ipairs(all_urls()) do
            assert(loader:held(u) == expected, ("%s: %s holds %d references"):format(label, u, loader:held(u)))
        end
        assert(loader.bad_unloads == 0, label .. ": unload of an unheld URL")
    end
    local failures = {}
    local function scenario(name, body)
        local ok, failure = pcall(body)
        if not ok then failures[#failures + 1] = name .. ": " .. tostring(failure) end
        Managers = saved_managers
    end

    scenario("all nine icons load once and draw in every mode", function()
        load_mod(true)
        hud = new_hud()
        assert(show("live_dog", "DOG READY", 0) == nil, "text while loading")
        loader:complete()
        each_mode(function()
            for i, alert in ipairs(alerts) do
                assert(show(alert[1], alert[2], i) ~= nil or settings.alert_display == "text", alert[2])
            end
        end)
        refs_each(1, "loaded")
        assert(simple_assets.files == 18)
        hud:destroy()
    end)

    scenario("a failed URL recovers on a later retry, not every frame", function()
        load_mod(true)
        loader.fail[url("live_dog", 64)], loader.fail[url("live_dog", 128)] = 1, 1
        hud = new_hud()
        loader:complete()
        each_mode(function() show("live_dog", "DOG READY", 1) end)
        settings.alert_display = "icon"
        assert(show("live_dog", "DOG READY", 1) == nil and hud.rendered.label, "text while the dog icon is missing")
        assert(loader:held(url("live_dog")) == 0, "failed reference given back before the retry")
        local first = icons.texture("live_task", 28)
        frames(1, 5)
        assert(simple_assets.files == 18, "no retry before the delay")
        frames(6, 6)
        assert(simple_assets.files == 20 and simple_assets.requested[icons.path(64, "live_dog")] == 2, "one retry of the two failed files")
        frames(7, 8)
        assert(simple_assets.files == 20, "no retry while loading")
        loader:complete()
        assert(loader.requests[url("live_dog")] == 2, "vanilla's cached failure cleared, so the retry reached the backend")
        assert(show("live_dog", "DOG READY", 9) ~= nil, "dog icon after the retry")
        assert(icons.texture("live_task", 28) == first and loader.requests[url("live_task")] == 1, "loaded icons kept")
        refs_each(1, "after retry")
        frames(10, 200)
        assert(simple_assets.files == 20, "nothing left to retry")
        hud:destroy()
    end)

    scenario("permanent failure is bounded and keeps text", function()
        load_mod(true)
        loader.fail[url("live_dog", 64)], loader.fail[url("live_dog", 128)] = true, true
        hud = new_hud()
        loader:complete()
        for t = 1, 400 do
            hud:draw(0, t)
            loader:complete()
        end
        assert(simple_assets.requested[icons.path(64, "live_dog")] == 3 and simple_assets.files == 22, "three attempts in all, got " .. simple_assets.files)
        assert(loader:held(url("live_dog")) == 0 and loader:held(url("live_dog", 128)) == 0)
        each_mode(function(mode)
            assert(show("live_dog", "DOG READY", 401) == nil and hud.rendered.label, "DOG READY as text in " .. mode)
            assert((show("live_task", "TASK", 402) ~= nil) == (mode ~= "text"), "TASK icon in " .. mode)
        end)
        hud:destroy()
        -- Every file failing: text in all modes, three attempts, no references held.
        load_mod(true)
        for _, u in ipairs(all_urls()) do loader.fail[u] = true end
        hud = new_hud()
        loader:complete()
        for t = 1, 400 do
            hud:draw(0, t)
            loader:complete()
        end
        assert(simple_assets.files == 54 and icons.state.status == "failed")
        each_mode(function()
            for i, alert in ipairs(alerts) do assert(show(alert[1], alert[2], 400 + i) == nil and hud.rendered.label) end
        end)
        refs_each(0, "all failed")
        hud:destroy()
    end)

    scenario("partial batch failure retries only the failed files", function()
        load_mod(true, function()
            simple_assets.unreadable[icons.path(64, "live_ability")] = 1 -- Read error: no URL, no reference.
        end)
        loader.fail[url("live_stimm", 64)], loader.fail[url("live_task", 128)] = 2, 1
        hud = new_hud()
        loader:complete()
        assert(show("live_task", "TASK", 0) ~= nil, "TASK keeps its 64 px icon")
        assert(show("live_ability", "ABILITY READY", 0).path:find("/128/", 1, true), "the other export meanwhile")
        assert(icons.texture("live_stimm", 28).path:find("/128/", 1, true))
        local kept = icons.texture("live_low_mag", 28)
        frames(1, 6)
        assert(simple_assets.files == 21)
        loader:complete()
        frames(7, 7) -- Starts the second delay for the stimm file.
        frames(37, 37)
        assert(simple_assets.files == 22 and simple_assets.requested[icons.path(64, "live_stimm")] == 3)
        loader:complete()
        for i, alert in ipairs(alerts) do assert(show(alert[1], alert[2], 40 + i) ~= nil, alert[2]) end
        for _, key in ipairs({"live_stimm", "live_ability", "live_task"}) do
            assert(icons.texture(key, 28).path:find("/64/", 1, true) and icons.texture(key, 100).path:find("/128/", 1, true))
        end
        assert(icons.texture("live_low_mag", 28) == kept and loader.requests[url("live_low_mag")] == 1)
        refs_each(1, "partial")
        hud:destroy()
    end)

    scenario("HUD recreation and missions reuse one set of references", function()
        load_mod(true)
        new_hud():destroy() -- A mission change while loading: no second request.
        loader:complete()
        local first = icons.texture("live_blitz", 28)
        for mission = 1, 5 do
            hud = new_hud(0)
            assert(show("live_blitz", "GRENADE +1", mission) == first)
            hud:destroy()
        end
        assert(simple_assets.files == 18 and not first.released)
        refs_each(1, "five HUDs")
    end)

    scenario("developer reloads release and reacquire without duplicates", function()
        load_mod(true)
        loader:complete()
        local previous = {}
        for cycle = 1, 3 do
            hud = new_hud()
            local drawn = show("live_toughness", "TOUGHNESS", 1)
            hud:destroy() -- DMF removes the HUD element before on_unload.
            self.on_unload(false)
            assert(drawn.released, "cycle " .. cycle .. ": old texture destroyed")
            refs_each(0, "unloaded " .. cycle)
            previous[#previous + 1] = drawn
            load_mod(false)
            loader:complete()
            refs_each(1, "reloaded " .. cycle)
            hud = new_hud()
            assert(show("live_toughness", "TOUGHNESS", 2) ~= drawn)
            hud:destroy()
        end
        self.on_unload(false)
        refs_each(0, "final unload")
        for _, texture in ipairs(loader.textures) do assert(texture.released, "leaked " .. texture.url) end
    end)

    scenario("completion after teardown is given back and never drawn", function()
        load_mod(true)
        hud = new_hud()
        hud:destroy()
        self.on_unload(false)
        loader:complete()
        refs_each(0, "late completion")
        for _, texture in ipairs(loader.textures) do assert(texture.released) end
        assert(icons.texture("live_dog", 28) == nil and icons.request(simple_assets) and simple_assets.files == 18)
        -- A retry waiting or in flight at unload stops there.
        load_mod(true)
        loader.fail[url("live_dog")] = 1
        hud = new_hud()
        loader:complete()
        frames(1, 6)
        assert(simple_assets.files == 19)
        hud:destroy()
        self.on_unload(false)
        loader:complete()
        refs_each(0, "retry after unload")
        hud = new_hud()
        frames(7, 300)
        assert(simple_assets.files == 19 and show("live_dog", "DOG READY", 301) == nil and hud.rendered.label)
        hud:destroy()
        -- Game exit after the loader is gone: nothing raises.
        load_mod(true)
        loader:complete()
        Managers = saved_managers
        self.on_unload(true)
    end)

    scenario("a request that raises costs only its own file", function()
        load_mod(true, function()
            simple_assets.raise[icons.path(64, "live_dog")] = "before" -- Raises before any reference is taken.
        end)
        hud = new_hud()
        loader:complete()
        for i, alert in ipairs(alerts) do assert(show(alert[1], alert[2], i / 10) ~= nil, alert[2] .. " after a raise") end
        assert(icons.texture("live_dog", 28).path:find("/128/", 1, true))
        for _, u in ipairs(all_urls()) do
            assert(loader:held(u) == (u == url("live_dog") and 0 or 1), u)
        end
        frames(1, 6)
        loader:complete()
        assert(icons.texture("live_dog", 28).path:find("/64/", 1, true) and simple_assets.files == 19)
        refs_each(1, "raise retried")
        hud:destroy()
        self.on_unload(false)
        refs_each(0, "raise unloaded")
    end)

    scenario("a request that never settles holds back nothing else", function()
        load_mod(true)
        loader.hold[url("live_task")], loader.fail[url("live_dog")] = true, 1
        hud = new_hud()
        loader:complete()
        for i, alert in ipairs(alerts) do assert(show(alert[1], alert[2], i / 10) ~= nil, alert[2] .. " beside a stalled file") end
        assert(icons.texture("live_task", 28).path:find("/128/", 1, true))
        frames(1, 6) -- The dog retry is not held up by the stalled TASK file.
        assert(simple_assets.files == 19)
        loader:complete()
        assert(icons.texture("live_dog", 28).path:find("/64/", 1, true))
        hud:destroy()
        self.on_unload(false)
        for _, u in ipairs(all_urls()) do
            assert(loader:held(u) == (u == url("live_task") and 1 or 0), u .. " after unload")
        end
        loader.hold = {}
        loader:complete() -- Settles after unload: given back, never stored.
        refs_each(0, "stalled file settled late")
        assert(icons.texture("live_task", 28) == nil)
    end)

    scenario("references the loader could not take back are returned by the next load", function()
        load_mod(true)
        loader:complete()
        local with_loader = Managers
        Managers = saved_managers -- The loader is briefly unavailable during unload.
        self.on_unload(false)
        Managers = with_loader
        refs_each(1, "owed after unload")
        load_mod(false)
        loader:complete()
        refs_each(1, "next load returned what was owed")
        -- Owed to a loader that has since been replaced: never given to the new one.
        local old_loader = loader
        Managers = saved_managers
        self.on_unload(false)
        load_mod(true)
        loader:complete()
        refs_each(1, "new loader")
        assert(old_loader.bad_unloads == 0)
        self.on_unload(false)
        refs_each(0, "final")
    end)

    Managers = saved_managers
    self.reset_icons(self.new_simple_assets(), true)
    settings.preview, settings.live_broken, settings.alert_display = false, false, "icon_text"
    assert(#failures == 0, "\n  " .. table.concat(failures, "\n  "))
    print("PASS: 0.9.5 texture lifecycle: nine icons in all modes, bounded retry past vanilla's cached failure, permanent and partial failure as text, HUD recreation, developer reloads, late completion, no leaked loader references; 0.9.6: a raising or stalled file costs only itself, references owed at unload returned by the next load")
end

function mod:test_style_timeline(device, map, ammo_components, slot, template)
    local hud_class = dofile(self.hud.filename .. ".lua")
    local ability = dofile("tests/ability_stub.lua")(
        {name = "adamant_charge", charges = 1, max = 1, can_use = true},
        {name = "veteran_frag_grenade", charges = 1, max = 3})
    local combat, grenade = ability.slots.combat_ability, ability.slots.grenade_ability
    local toughness = {maximum = 100, remaining = 100,
        max_toughness = function(self) return self.maximum end,
        remaining_toughness = function(self) return self.remaining end}
    local unit, item = {}, {}
    local loadout = {item_from_slot = function() return item end}
    local data = {read_component = function(_, key)
        return ammo_components[key] or assert(components[key])
    end}
    local parent = {
        player_unit = function() return unit end,
        player_extensions = function()
            return {unit = unit, unit_data = data, toughness = toughness, ability = ability, visual_loadout = loadout}
        end,
    }
    local inventory, action = ammo_components.inventory, ammo_components.weapon_action
    inventory.wielded_slot, action.slot_name = "slot_secondary", "slot_secondary"
    action.template, action.current_action_name = template, "none"
    slot.clips[1], slot.clips[2], slot.max_mag, slot.reserve, slot.max_reserve = 8, 0, 10, 80, 100
    map.a, device.interrupted = device, false
    settings.ability_diagnostics, settings.live_broken = true, true
    local user_color = {255, 240, 110, 160} -- A saved Notification colour must survive.
    settings.alert_color = user_color
    local hud = setmetatable({}, {__index = hud_class})
    hud:init(parent, 0, 1)
    local widget = hud._widgets_by_name.alert
    local function frame(t, expected, rgb)
        local previous = hud.draws or 0
        hud:draw(0, t)
        local actual = hud.draws ~= previous and widget.content.message or nil
        assert(actual == expected, ("%s: expected %s, got %s"):format(t, tostring(expected), tostring(actual)))
        if actual then
            mod.check_symbols(hud, actual)
        end
        if rgb then
            local got = table.concat(widget.style.label.text_color, ",", 2, 4)
            assert(got == rgb, ("%s %s: colour %s, expected %s"):format(t, expected, got, rgb))
            assert(widget.content.marker == nil and widget.style.marker == nil, t .. " no underline")
        end
    end
    local function diagnostics(command)
        self.capture_echo = {}
        self[command]()
        local lines = self.capture_echo
        self.capture_echo = nil
        return lines[1], lines[2] or ""
    end

    frame(0)
    -- RELOAD is a fixed amber label; AMMO LOW is red, with no underline (0.9.1).
    slot.clips[1] = 2
    frame(0.2, "RELOAD", "255,200,61")
    frame(2.8)
    slot.clips[1], slot.reserve = 8, 8 -- Pickup-free stub jump to 16 of 110 total.
    frame(3.0, "AMMO LOW", "255,77,77")
    frame(5.6)
    -- A deferred RELOAD keeps the same fixed label; no round count appears.
    slot.reserve = 80
    frame(5.8)
    device.interrupted = true
    frame(6.0, "TASK", "240,110,160") -- TASK keeps the player's own colour.
    slot.clips[1] = 2
    frame(6.2, "TASK")
    slot.clips[1] = 1
    frame(6.4, "TASK")
    frame(11.1, "RELOAD", "255,200,61")
    device.interrupted = false
    frame(13.7)
    slot.clips[1] = 8
    frame(13.8)
    -- Toughness cyan, BROKEN red: unchanged detection, new colours only.
    toughness.remaining = 20
    frame(14.0, "TOUGHNESS", "77,210,255")
    frame(16.6)
    toughness.remaining = 100
    frame(16.8)
    toughness.remaining = 0
    frame(17.0, "BROKEN", "255,77,77")
    frame(19.6)
    toughness.remaining = 100
    frame(19.8)
    -- Ability golden yellow, grenade grey, dog lavender.
    combat.charges = 0
    frame(20.0)
    combat.charges = 1
    frame(20.2, "ABILITY READY", "255,214,40")
    frame(22.3)
    grenade.charges = 2
    frame(22.45, "GRENADE +1", "215,215,215") -- 22.3 + 0.1 sampling lands just past 22.4.
    frame(24.5)
    grenade.name, grenade.charges, grenade.max = "adamant_whistle", 0, 2
    frame(24.6)
    grenade.charges = 1
    frame(24.8, "DOG READY", "200,168,255")
    frame(26.9)
    grenade.name, grenade.charges, grenade.max = "veteran_frag_grenade", 1, 3
    frame(27.0)
    -- Category colours off: every alert uses the saved Notification colour, AMMO LOW included.
    settings.category_colors = false
    slot.clips[1] = 2
    frame(27.2, "RELOAD", "240,110,160")
    frame(29.8)
    slot.clips[1], slot.reserve = 8, 8 -- Pickup-free stub jump to 16 of 110 total.
    frame(30.0, "AMMO LOW", "240,110,160")
    frame(32.6)
    settings.category_colors = true
    slot.reserve = 80
    frame(32.8)
    -- Previews keep the saved colour.
    settings.preview = true
    self.preview()
    frame(33.0, "TEST ALERT", "240,110,160") -- The next live alert replaces the brief preview.
    assert(user_color[1] == 255 and user_color[2] == 240) -- Never written to.

    -- Regenerated grenades notify; the player's own pickups stay silent.
    grenade.charges = 2
    frame(33.6, "GRENADE +1")
    frame(35.7)
    self.pickup_hooks[1].callback({}, nil, unit, {}, 0, "success")
    frame(35.9)
    grenade.charges = 3
    frame(36.1) -- Charge arrives after the pickup: silent.
    assert(diagnostics("ability_command"):find("silent GRENADE +1: pickup", 1, true))
    grenade.charges = 1
    frame(37.5)
    grenade.charges = 2
    frame(38.3, "GRENADE +1") -- Outside the two-second window: regeneration again.
    frame(40.4)
    self.pickup_hooks[2].callback({}, nil, {}, {}, 0, "success")
    grenade.charges = 3
    frame(40.5, "GRENADE +1") -- Another player's pickup doesn't silence ours.

    -- Rescue keeps state; respawn baselines silently.
    combat.charges = 0
    frame(42.6)
    disabled.is_disabled = true
    frame(42.8)
    combat.charges = 1 -- Recharged while netted.
    frame(43.0)
    disabled.is_disabled = false
    frame(43.2, "ABILITY READY")
    unit = {}
    combat.charges = 0
    frame(45.4)
    frame(45.6)

    hud:destroy()
    settings.ability_diagnostics, settings.live_broken, settings.alert_color, settings.preview = false, false, nil, false
    print("PASS: alert styling: fixed RELOAD label, AMMO LOW without underline, golden ABILITY READY, category colours, saved colour, toggle off, previews, pickups, rescue and respawn")
end

dofile("tests/test_gameplay.lua")
