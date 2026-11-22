-- Test double for PlayerUnitAbilityExtension. It reproduces the getter semantics
-- read from the decompiled source: remaining/max charges report 0 while a slot is
-- disabled, max is 0 for abilities without charges, and can_use_ability is
-- independent of the charge count (free-use buffs, locked-while-active).
return function(combat, grenade)
    local ext = {slots = {combat_ability = combat, grenade_ability = grenade}}
    local function slot(self, ability_type) return assert(self.slots[ability_type], ability_type) end
    function ext:ability_is_equipped(t) return slot(self, t).equipped ~= false end
    function ext:ability_enabled(t) return slot(self, t).enabled ~= false end
    function ext:uses_ability_charges(t) return self:ability_is_equipped(t) and slot(self, t).uses ~= false end
    function ext:ability_name(t) return slot(self, t).name end
    function ext:remaining_ability_charges(t)
        return self:ability_enabled(t) and slot(self, t).charges or 0
    end
    function ext:max_ability_charges(t)
        if not self:ability_enabled(t) or not self:uses_ability_charges(t) then
            return 0
        end
        return slot(self, t).max
    end
    function ext:can_use_ability(t) return slot(self, t).can_use == true end
    function ext:get_ability_resource_regen_progress(t) return slot(self, t).progress or 0 end
    function ext:is_ability_resource_regen_paused(t) return slot(self, t).paused == true end
    return ext
end
