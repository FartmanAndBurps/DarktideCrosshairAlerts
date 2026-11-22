local mod = get_mod("DarktideCrosshairAlerts")
-- Dot-first: every reticle becomes the custom dot except the few vanilla types
-- that carry information the dot template can't draw, or that mean "no reticle".
-- All ordinary reticles (assault, bfg, cross, flamer, shotgun, shotgun_wide,
-- spray_n_pray, dot_special) draw only spread segments plus the shared hit
-- markers, which the dot template also draws. Unknown future types get the dot.
local preserved = {
    ironsight = true, -- Genuine ADS: deliberately no reticle, hit markers only.
    charge_up = true, -- Charge bars (staffs); its centre is restyled as the dot below.
    charge_up_ads = true, -- Charge bars while aiming down sights (Helbore).
    projectile_drop = true, -- Drop ladder for arcing projectiles (gauntlet, Rumbler).
    none = true, -- Intentionally no reticle (reloads and similar actions).
    dot = true, -- Already the dot.
}
local hooked_classes = setmetatable({}, {__mode = "k"})
local fallback_color = {255, 80, 235, 255}
-- Weapons whose alternate fire is a true sight resolve to one of these
-- (autogun_p1 ironsight, helbore charge_up_ads, gauntlet projectile_drop).
-- Braced weapons resolve to an ordinary spread type instead (heavy stubber
-- spray_n_pray, shotpistol and shield shotgun), so they keep the custom dot.
local sighted = {ironsight = true, charge_up_ads = true, projectile_drop = true}
local WeaponTemplate

local function wielded_template(unit_data)
    WeaponTemplate = WeaponTemplate or require("scripts/utilities/weapon/weapon_template")
    return WeaponTemplate.current_weapon_template(unit_data:read_component("weapon_action"))
end

local function alternate_fire_crosshair(unit_data)
    local template = wielded_template(unit_data)
    local settings = template and template.alternate_fire_settings
    return settings and settings.crosshair
end


-- Returns "hip", "braced" or "sighted", or nil when the state can't be read.
local function aim_mode(element)
    local parent = element._parent
    local extensions = parent and parent.player_extensions and parent:player_extensions()
    local unit_data = extensions and extensions.unit_data
    if not (unit_data and unit_data.read_component) then
        return
    end
    local ok, component = pcall(unit_data.read_component, unit_data, "alternate_fire")
    if not ok or not component or type(component.is_active) ~= "boolean" then
        return
    end
    if not component.is_active then
        return "hip"
    end
    local found, crosshair = pcall(alternate_fire_crosshair, unit_data)
    if found and crosshair and sighted[crosshair.crosshair_type] then
        return "sighted"
    end
    return "braced"
end

mod:hook_require("scripts/ui/hud/elements/crosshair/hud_element_crosshair", function(crosshair)
    if type(crosshair) ~= "table" or type(crosshair._get_current_crosshair_type) ~= "function"
        or type(crosshair._draw_widgets) ~= "function" or hooked_classes[crosshair] then
        return
    end

    -- The vanilla resolver already returns a sight type during true ADS (and
    -- "ironsight" when vanilla's own crosshair option is off), so any other type
    -- here means hip fire, bracing or an alternate-fire spread; all use the dot.
    mod:hook(crosshair, "_get_current_crosshair_type", function(next_hook, self, settings)
        local resolved = next_hook(self, settings)
        if mod:get("crosshair") and settings
            and self._crosshair_templates and self._crosshair_templates.dot
            and self._crosshair_widget_definitions and self._crosshair_widget_definitions.dot
            and type(resolved) == "string" and not preserved[resolved] then
            return "dot"
        end
        return resolved
    end)

    mod:hook(crosshair, "_draw_widgets", function(next_hook, self, ...)
        local kind = self._crosshair_type
        local widget = self._widget
        local centre = widget and widget.style and widget.style.center
        if not mod:get("crosshair") or (kind ~= "dot" and kind ~= "charge_up")
            or not (centre and centre.size and centre.color) then
            return next_hook(self, ...)
        end

        local mode = aim_mode(self)
        if mode == nil then
            return next_hook(self, ...)
        end

        local old_color, old_size = centre.color, centre.size
        local color = mod:get("dot_color") or fallback_color
        local size = mod:get("dot_size") or 6
        local opacity = mod:get("dot_opacity") or 100
        -- Only the centre pass changes; charge bars and hit markers draw as vanilla.
        local hidden = mode == "sighted"
        centre.color = { hidden and 0 or math.floor(opacity * 255 / 100 + 0.5), color[2], color[3], color[4] }
        centre.size = {size, size}
        -- Scope the change to this draw so toggling off needs no widget or template cleanup.
        local ok, failure = pcall(next_hook, self, ...)
        centre.color, centre.size = old_color, old_size
        if not ok then
            error(failure, 0)
        end
    end)

    -- DMF can report the same class for multiple tracked instances of the file.
    -- This cache lives for one mod load, alongside DMF's hook registrations.
    hooked_classes[crosshair] = true
end)

mod.gameplay_alerts = mod:io_dofile("DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/gameplay_alerts")
mod.icons = mod:io_dofile("DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/icon_textures")

-- Simple Assets is optional: look it up once every mod has loaded, and again
-- when a HUD is created (covers a DMF reload). Repeated calls never reload.
function mod.request_icons()
    return mod.icons.request(get_mod("SimpleAssets"))
end

function mod.on_all_mods_loaded()
    mod.request_icons()
end

-- Called by the HUD each frame with its time: a field check unless a failed
-- icon's retry is due, which then requests only the failed files.
function mod.update_icons(t)
    local icons = mod.icons
    if icons and icons.retry_due(t) then
        return icons.retry(get_mod("SimpleAssets"))
    end
end

-- DMF reload (after it has destroyed the HUD element) or game exit: give back
-- every URL-loader reference this load of the mod acquired.
function mod.on_unload()
    if mod.icons then
        mod.icons.release()
    end
end

if type(mod.register_hud_element) == "function" then
    mod:register_hud_element({
        class_name = "HudElementDarktideCrosshairAlerts",
        filename = "DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/notification_hud",
        visibility_groups = {"alive"},
        allowed_game_modes = {"coop_complete_objective", "shooting_range"},
        use_hud_scale = true,
    })
end

function mod.on_disabled()
    if mod.preview_element then
        mod.preview_element:clear_preview()
        mod.preview_element:reset_live_alerts()
    end
end

local function preview_command(mode)
    local element = mod.preview_element
    if mode == "clear" then
        if element then
            element:dismiss_preview()
        end
    elseif element and mod:get("preview") and element:preview_unit() then
        element:show_preview(mode == "hold")
    else
        mod:echo(mod:localize("preview_unavailable"))
    end
end

function mod.preview_brief()
    preview_command()
end

mod:command("dca_preview", mod:localize("preview_command"), preview_command)

mod:command("dca_reserve", mod:localize("reserve_command"), function()
    local element = mod.preview_element
    if not mod:get("reserve_diagnostics") then
        mod:echo(mod:localize("reserve_diagnostics_off"))
    elseif element then
        local snapshot, history = element:reserve_diagnostics()
        mod:echo("%s", snapshot)
        if history then
            mod:echo("%s", history)
        end
    else
        mod:echo(mod:localize("reserve_no_sample", "n/a", "no active HUD", "none"))
    end
end)

mod:command("dca_toughness", mod:localize("toughness_command"), function()
    local element = mod.preview_element
    if not mod:get("toughness_diagnostics") then
        mod:echo(mod:localize("toughness_diagnostics_off"))
    elseif element then
        local snapshot, history = element:toughness_diagnostics()
        mod:echo("%s", snapshot)
        if history then
            mod:echo("%s", history)
        end
    else
        mod:echo(mod:localize("toughness_no_sample", "no active HUD (not alive, disabled or outside a mission)"))
    end
end)

mod:command("dca_ability", mod:localize("ability_command"), function()
    local element = mod.preview_element
    if not mod:get("ability_diagnostics") then
        mod:echo(mod:localize("ability_diagnostics_off"))
    elseif element then
        local snapshot, history = element:ability_diagnostics()
        mod:echo("%s", snapshot)
        if history then
            mod:echo("%s", history)
        end
    else
        mod:echo(mod:localize("ability_no_sample", "no active HUD (not alive, disabled or outside a mission)"))
    end
end)

mod:command("dca_mag", mod:localize("mag_command"), function()
    local element = mod.preview_element
    if not mod:get("mag_diagnostics") then
        mod:echo(mod:localize("mag_diagnostics_off"))
    elseif element then
        local snapshot, history = element:mag_diagnostics()
        mod:echo("%s", snapshot)
        if history then
            mod:echo("%s", history)
        end
    else
        mod:echo(mod:localize("mag_no_sample", mod:get("mag_threshold"), "no active HUD"))
    end
end)
