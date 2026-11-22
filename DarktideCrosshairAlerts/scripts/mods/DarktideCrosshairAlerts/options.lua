local mod = get_mod("DarktideCrosshairAlerts")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            { setting_id = "group_crosshair", type = "group", sub_widgets = {
                { setting_id = "crosshair", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "dot_color", type = "color", default_value = {255, 80, 235, 255} },
                    { setting_id = "dot_size", type = "numeric", default_value = 6, range = {2, 16} },
                    { setting_id = "dot_opacity", type = "numeric", default_value = 100, range = {0, 100} },
                } },
            } },
            { setting_id = "group_appearance", type = "group", sub_widgets = {
                { setting_id = "alert_color", type = "color", default_value = {255, 255, 245, 107} },
                { setting_id = "alert_size", type = "numeric", default_value = 23, range = {14, 48} },
                { setting_id = "alert_offset", type = "numeric", default_value = 60, range = {30, 250} },
                { setting_id = "category_colors", type = "checkbox", default_value = true },
                { setting_id = "alert_display", type = "dropdown", default_value = "icon_text", options = {
                    { text = "alert_display_text", value = "text" },
                    { text = "alert_display_icon", value = "icon" },
                    { text = "alert_display_icon_text", value = "icon_text" },
                } },
            } },
            { setting_id = "group_mission", type = "group", sub_widgets = {
                { setting_id = "live_task", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "task_size", type = "numeric", default_value = 26, range = {14, 48} },
                    { setting_id = "live_task_duration", type = "numeric", default_value = 5, range = {1, 8}, decimals_number = 1, step_size_value = 0.5 },
                } },
            } },
            { setting_id = "group_ammo", type = "group", sub_widgets = {
                { setting_id = "live_low_mag", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "mag_threshold", type = "numeric", default_value = 20, range = {1, 100} },
                    { setting_id = "mag_min_rounds", type = "numeric", default_value = 1, range = {0, 5} },
                    { setting_id = "live_low_mag_duration", type = "numeric", default_value = 2.5, range = {1, 6}, decimals_number = 1, step_size_value = 0.5 },
                } },
                { setting_id = "live_low_ammo", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "reserve_threshold", type = "numeric", default_value = 25, range = {1, 100} },
                    { setting_id = "live_low_ammo_duration", type = "numeric", default_value = 2.5, range = {1, 6}, decimals_number = 1, step_size_value = 0.5 },
                } },
            } },
            { setting_id = "group_toughness", type = "group", sub_widgets = {
                { setting_id = "live_toughness", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "toughness_threshold", type = "numeric", default_value = 25, range = {1, 95} },
                    { setting_id = "toughness_recovery", type = "numeric", default_value = 50, range = {2, 99} },
                } },
                { setting_id = "live_broken", type = "checkbox", default_value = false },
            } },
            { setting_id = "group_abilities", type = "group", sub_widgets = {
                { setting_id = "live_ability", type = "checkbox", default_value = true },
                { setting_id = "live_blitz", type = "checkbox", default_value = true },
                { setting_id = "live_dog", type = "checkbox", default_value = true },
                { setting_id = "ability_alert_duration", type = "numeric", default_value = 2, range = {1, 6}, decimals_number = 1, step_size_value = 0.5 },
            } },
            { setting_id = "group_stimm", type = "group", sub_widgets = {
                { setting_id = "live_stimm", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "stimm_threshold", type = "numeric", default_value = 3, range = {1, 10} },
                } },
            } },
            { setting_id = "group_testing", type = "group", sub_widgets = {
                { setting_id = "preview", type = "checkbox", default_value = true, sub_widgets = {
                    { setting_id = "preview_key", type = "keybind", default_value = {""},
                      keybind_trigger = "pressed", keybind_type = "function_call", function_name = "preview_brief" },
                    { setting_id = "alert_duration", type = "numeric", default_value = 2, range = {1, 6}, decimals_number = 1, step_size_value = 0.5 },
                } },
                { setting_id = "mag_diagnostics", type = "checkbox", default_value = false },
                { setting_id = "reserve_diagnostics", type = "checkbox", default_value = false },
                { setting_id = "toughness_diagnostics", type = "checkbox", default_value = false },
                { setting_id = "ability_diagnostics", type = "checkbox", default_value = false },
            } },
        },
    },
}
