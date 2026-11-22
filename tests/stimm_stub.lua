-- Minimal model of vanilla Buff and BuffExtensionBase (scripts/extension_systems/buff)
-- for stimm tests: duration() adds extra_duration, duration_progress() mirrors
-- _update_duration, and unique_buff_id replacement mirrors _handle_unique_buffs.
return function()
    local extension = {now = 0, list = {}}
    local Buff = {}
    Buff.__index = Buff
    function Buff:template() return self._template end
    function Buff:duration()
        local duration = self._template.duration
        if self.extra then
            duration = (duration or 0) + self.extra
        end
        return duration
    end
    function Buff:duration_progress()
        local duration = self:duration()
        if not duration then
            return 1
        end
        return math.max(0, math.min(1, (duration - (extension.now - self.start)) / duration))
    end
    function Buff:finished()
        local duration = self:duration()
        return duration ~= nil and extension.now > self.start + duration
    end
    function Buff:add_duration(amount) self.extra = (self.extra or 0) + amount end
    function Buff:set_start_time(t) self.start = t end

    function extension:buffs() return self.list end
    function extension:add(template, extra)
        for i = #self.list, 1, -1 do
            local id = self.list[i]._template.unique_buff_id
            if template.unique_buff_id and id == template.unique_buff_id then
                table.remove(self.list, i)
            end
        end
        local buff = setmetatable({_template = template, start = self.now}, Buff)
        if extra then
            buff:add_duration(extra) -- Stimm Lab's syringe_duration stat, applied in start_func.
        end
        self.list[#self.list + 1] = buff
        return buff
    end
    function extension:remove_finished()
        for i = #self.list, 1, -1 do
            if self.list[i]:finished() then
                table.remove(self.list, i)
            end
        end
    end
    extension.templates = {
        broker = {name = "syringe_broker_buff", duration = 15, unique_buff_id = "syringe_stimm", unique_buff_priority = 1},
        power = {name = "syringe_power_boost_buff", duration = 15, unique_buff_id = "syringe_stimm", unique_buff_priority = 1},
        -- BrokerBuffUtils clears duration and unique_buff_id on Stimm Supply variants.
        field = {name = "syringe_broker_buff_stimm_field", keywords = {"syringe", "syringe_broker"}},
        heal = {name = "syringe_heal_corruption_buff", duration = 8},
        talent = {name = "broker_syringe_toughness_over_time", duration = 5},
    }
    return extension
end
