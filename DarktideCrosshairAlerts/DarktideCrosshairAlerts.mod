return {
    run = function()
        local path = "DarktideCrosshairAlerts/scripts/mods/DarktideCrosshairAlerts/"
        new_mod("DarktideCrosshairAlerts", {
            mod_script = path .. "main",
            mod_data = path .. "options",
            mod_localization = path .. "localization",
        })
    end,
}
