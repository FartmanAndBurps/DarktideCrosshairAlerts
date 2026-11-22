local Gameplay = get_mod("DarktideCrosshairAlerts").gameplay_alerts

local function decoder()
    return {
        placed = true, started = true,
        is_finished = function(self) return self.finished == true end,
        decoding_interrupted = function(self) return self.interrupted == true end,
        wait_for_restart = function(self)
            return self.placed and self.started and self.interrupted and not self.busy
        end,
    }
end
local a, b = decoder(), decoder()
local map = {a = a}
local system = {unit_to_extension_map = function() return map end}
local manager = {system = function(_, name)
    assert(name == "decoder_device_system")
    return system
end}
local state = {}
local function task(expected, enabled)
    assert(Gameplay.task(state, manager, enabled ~= false) == expected)
end

a.started = false
a.interrupted = true
task(nil)
a.started, a.interrupted = true, false
task(nil)
a.interrupted = true
task("live_task")
task(nil)
a.busy = true
task(nil)
a.busy = false
task(nil) -- Failed/cancelled minigame during the same interruption.
a.interrupted = false
task(nil)
a.interrupted = true
task("live_task")
map.b = b
b.interrupted = true
task("live_task")
task(nil)
b.finished = true
task(nil)
assert(Gameplay.task(state, nil, true) == nil)
map.bad = {}
task(nil)
map.bad = nil

-- The RPC provides completion even though the extension's sync method doesn't store it.
local mod = get_mod("DarktideCrosshairAlerts")
local decoder_class = {hot_join_sync = function() end}
mod.require_callbacks["scripts/extension_systems/decoder_device/decoder_device_extension"](decoder_class)
mod.require_callbacks["scripts/extension_systems/decoder_device/decoder_device_extension"](decoder_class)
assert(mod.safe_hook_count == 1)
local joined = decoder()
joined.interrupted = true
map.joined = joined
mod.hot_join_callback(joined, true, true, true, true, true)
task(nil)
mod.hot_join_callback(joined, true, true, true, true, false)
task("live_task")
task(nil)
local old_system = system
system = {unit_to_extension_map = function() return map end}
task("live_task")
task(nil)
system = old_system
task(nil, false)
task(nil)
print("PASS: client decoder setup, genuine stalls, duplicate suppression, restart, completion and hot join")

local template = {ranged = true, hud_configuration = {uses_ammunition = true}, actions = {
    action_reload_shell = {kind = "reload_shell"},
}}
local template_module = {
    is_ranged = function(value) return value.ranged end,
    is_melee = function(value) return value.melee end,
    current_weapon_template = function(action) return action.template or template end,
}
package.loaded["scripts/utilities/weapon/weapon_template"] = template_module
package.loaded["scripts/utilities/ammo"] = {
    current_ammo_in_clips = function(slot) return slot.clips[1] + slot.clips[2] end,
    max_ammo_in_clips = function(slot) return slot.max_mag end,
    current_ammo_in_reserve = function(slot) return slot.reserve end,
    max_ammo_in_reserve = function(slot) return slot.max_reserve end,
}
local slot = {clips = {0, 0}, max_mag = 10, reserve = 0, max_reserve = 100}
local inventory = {wielded_slot = "slot_secondary"}
local action = {slot_name = "slot_secondary", current_action_name = "none"}
local components = {inventory = inventory, weapon_action = action, slot_secondary = slot}
local unit_data = {read_component = function(_, name) return assert(components[name]) end}
local ammo_state = {}
local function sample(mag, reserve, expected_mag, expected_reserve, second_clip, threshold)
    slot.clips[1], slot.clips[2], slot.reserve = mag, second_clip or 0, reserve
    local mag_alert, reserve_alert = Gameplay.ammo(ammo_state, unit_data, threshold or 20, 15)
    assert(mag_alert == expected_mag and reserve_alert == expected_reserve, ("%d/%d: %s %s"):format(mag, reserve, tostring(mag_alert), tostring(reserve_alert)))
end
-- Total supply is magazine plus reserve: 10 + 100 here, so below 15% means 16 or fewer.
local function reload(mag, reserve, second_clip)
    action.current_action_name = "action_reload_shell"
    sample(mag, reserve, nil, nil, second_clip)
    action.current_action_name = "none"
end
sample(1, 10) -- Initial low baseline is silent for both.
sample(0, 9)
sample(3, 40) -- A pickup lifts the total above the threshold and rearms it.
assert(ammo_state.reserve_outcome == "rearmed")
sample(2, 40, "live_low_mag") -- At or below 20% of ten rounds means two or fewer.
reload(0, 42) -- Vanilla reloads first return the magazine to reserve...
reload(10, 32) -- ...then refill it: the total never moves.
sample(7, 10, nil, nil) -- (Stub jump.) 17 of 110 is still above 15%.
sample(6, 10, nil, "live_low_ammo") -- A shot crosses the total: 16 of 110.
assert(ammo_state.reserve_outcome == "threshold crossed")
sample(5, 10) -- Already low: no repeat while firing.
reload(0, 15)
reload(10, 5) -- Reserve 15 -> 5 crossed 15% of reserve in 0.6.1; the total stays 15.
sample(2, 5, "live_low_mag") -- MAG and AMMO stay independent.
sample(2, 40) -- Pickup rearms.
assert(ammo_state.reserve_outcome == "rearmed" and not ammo_state.supply_low)
ammo_state = {}
sample(3, 14) -- Total 17.
sample(2, 14, "live_low_mag", "live_low_ammo") -- One shot can cross both.
ammo_state = {}
sample(5, 10, nil, nil, 3) -- Both clips count: 18 of 110.
sample(5, 10, nil, "live_low_ammo", 1) -- Second clip spent: 16.
ammo_state = {}
-- Free-transfer reload buffs empty the magazine before refilling it for free.
sample(6, 12) -- Total 18.
reload(0, 12) -- Total 12 during the reload is not spending ammunition.
assert(ammo_state.reserve_outcome == "crossing suppressed during reload")
reload(10, 12)
sample(10, 12)
sample(6, 12)
sample(4, 12, nil, "live_low_ammo") -- Firing after the reload still warns.

inventory.wielded_slot = "slot_primary"
assert(Gameplay.ammo(ammo_state, unit_data, 20, 15) == nil)
inventory.wielded_slot = "slot_secondary"
sample(4, 12) -- Same weapon after a swap keeps its low baseline: no repeat.
sample(4, 40)
inventory.wielded_slot = "slot_primary"
assert(Gameplay.ammo(ammo_state, unit_data, 20, 15) == nil)
inventory.wielded_slot = "slot_secondary"
sample(4, 10, nil, "live_low_ammo") -- (Stub jump.) The armed baseline survived the swap.
-- No reserve at all: LOW MAG only, never AMMO LOW.
ammo_state = {}
slot.max_reserve = 0
sample(10, 0)
sample(1, 0, "live_low_mag")
assert(ammo_state.reserve_outcome == "no ordinary reserve")
slot.max_reserve = 100
-- A single-round weapon never shows LOW MAG.
ammo_state = {}
slot.max_mag = 1
sample(1, 50)
sample(0, 50)
assert(ammo_state.mag_sample == "capacity 1: LOW MAG off")
slot.max_mag = 10
sample(5, 100)
sample(4, 100, nil, nil, nil, 50) -- Threshold change establishes a baseline.
sample(6, 100, nil, nil, nil, 50)
sample(4, 100, "live_low_mag", nil, nil, 50)
-- Default 25%: 27.5 of 110 total, so 27 is the first low value.
local function default_threshold(mag, expected)
    slot.clips[1], slot.clips[2] = mag, 0
    local _, alert = Gameplay.ammo(ammo_state, unit_data, 20, 25)
    assert(alert == expected, ("%d+%d: %s"):format(mag, slot.reserve, tostring(alert)))
end
ammo_state = {}
slot.reserve = 19
default_threshold(10) -- 29
default_threshold(9) -- 28 is not low.
default_threshold(8, "live_low_ammo") -- 27
default_threshold(7)
ammo_state = {}
template.hud_configuration.uses_ammunition = false
sample(0, 0)
template.hud_configuration.uses_ammunition = true
sample(0, 0)
assert(Gameplay.ammo(ammo_state, nil, 20, 15) == nil)

-- Small magazines. The Arbites shotpistol and shield has a five-round cylinder.
local function shots(capacity, threshold, min_rounds, steps)
    ammo_state = {}
    slot.max_mag, slot.clips[2], slot.reserve = capacity, 0, 50
    for _, step in ipairs(steps) do
        local mag, expected, reloading = step[1], step[2], step[3]
        slot.clips[1] = mag
        action.current_action_name = reloading and "action_reload_shell" or "none"
        local alert = Gameplay.ammo(ammo_state, unit_data, threshold, 15, nil, min_rounds)
        assert(alert == expected, ("%d-round %d%% min %d at %d: %s"):format(capacity, threshold,
            min_rounds, mag, tostring(alert)))
    end
    action.current_action_name = "none"
end
-- 20% of five is one round: warn on dropping from two to one, not at zero, and only once.
shots(5, 20, 0, {{5}, {4}, {3}, {2}, {1, "live_low_mag"}, {0}, {2, nil, true}, {5, nil, true}, {4}, {2}, {1, "live_low_mag"}, {0}})
shots(5, 20, 1, {{5}, {2}, {1, "live_low_mag"}, {0}})
-- The minimum-round warning covers a threshold that rounds to zero rounds.
shots(5, 10, 1, {{5}, {2}, {1, "live_low_mag"}, {0}})
shots(5, 10, 0, {{5}, {2}, {1}, {0, "live_low_mag"}})
-- Double-barrelled shotguns and single-shot weapons never warn, at any threshold.
shots(2, 20, 1, {{2}, {1}, {0}, {2, nil, true}, {1}, {0}})
shots(2, 100, 5, {{2}, {1}, {0}})
shots(1, 100, 1, {{1}, {0}, {1, nil, true}, {0}})
-- Three rounds is the smallest magazine that warns.
shots(3, 20, 1, {{3}, {2}, {1, "live_low_mag"}, {0}})
-- Larger magazines warn at the rounded share: 20% of 30 is six rounds.
shots(30, 20, 1, {{30}, {7}, {6, "live_low_mag"}, {5}, {1}})
-- A large magazine with one or two rounds left still warns; only capacity matters.
shots(30, 5, 0, {{30}, {3}, {1, "live_low_mag"}})
assert(Gameplay.mag_is_low(1, 5, 20, 0) and not Gameplay.mag_is_low(2, 5, 20, 0)
    and not Gameplay.mag_is_low(5, 5, 100, 1) and Gameplay.mag_is_low(3, 6, 1, 3)
    and not Gameplay.mag_is_low(1, 2, 1, 1) and Gameplay.mag_is_low(1, 3, 1, 1)
    and not Gameplay.mag_is_low(0, 2, 100, 1) and not Gameplay.mag_is_low(0, 1, 100, 1)
    and Gameplay.mag_is_low(0, 3, 20, 0) and Gameplay.mag_is_low(2, 30, 20, 0))
-- Changing the minimum-round setting establishes a silent baseline.
ammo_state = {}
slot.max_mag, slot.clips[1] = 5, 2
Gameplay.ammo(ammo_state, unit_data, 10, 15, nil, 0)
slot.clips[1] = 1
assert(Gameplay.ammo(ammo_state, unit_data, 10, 15, nil, 1) == nil)
slot.max_mag = 10
ammo_state = {}
print("PASS: small magazines, one- and two-round capacities silent, at-or-below rounding, minimum rounds and duplicate prevention")
assert(Gameplay.select("live_low_ammo", "live_task", "live_low_mag") == "live_task")
assert(Gameplay.select("live_task", nil, "live_low_mag", "live_low_ammo") == nil)
assert(Gameplay.select(nil, nil, "live_low_mag", "live_low_ammo") == "live_low_mag")
print("PASS: total-ammunition crossings on shots, invariant reloads, free-transfer dip, swaps, pickups, multi-clip, no-reserve weapons and priorities")

-- H1 (0.9.2 audit): a 25/100 -> 24/100 crossing in the same sample as a reload
-- starting was suppressed and then lost, because the reload sample became the
-- baseline. The last stable total is now kept through the reload.
do
    local saved = {slot.max_mag, slot.max_reserve}
    slot.max_mag, slot.max_reserve = 10, 90 -- 100 rounds in all; 25% is 25.
    local function supply(mag, reserve, reloading, expected)
        action.current_action_name = reloading and "action_reload_shell" or "none"
        slot.clips[1], slot.clips[2], slot.reserve = mag, 0, reserve
        local _, alert = Gameplay.ammo(ammo_state, unit_data, 20, 25)
        action.current_action_name = "none"
        assert(alert == expected, ("%d+%d%s: expected %s, got %s (%s)"):format(mag, reserve,
            reloading and " reloading" or "", tostring(expected), tostring(alert), tostring(ammo_state.reserve_outcome)))
        assert(ammo_state.reloading == (reloading == true))
    end
    -- Genuine crossing followed immediately by a reload: one AMMO LOW after it.
    ammo_state = {}
    supply(5, 20) -- 25/100: at the threshold, not below.
    supply(4, 20, true) -- The shot to 24 and the reload start land in one sample.
    assert(ammo_state.reserve_outcome == "crossing suppressed during reload" and ammo_state.total == 25)
    supply(0, 24, true) -- Vanilla returns the magazine to reserve...
    supply(10, 14, true) -- ...and refills it: still 24.
    supply(10, 14, false, "live_low_ammo") -- Reconciled against 25 when the reload ends.
    supply(10, 14) -- No duplicate.
    supply(9, 14)
    supply(9, 14, true)
    supply(9, 14) -- Another reload while already low: no duplicate.
    -- The same crossing without a reload warns at once, exactly as before.
    ammo_state = {}
    supply(5, 20)
    supply(4, 20, false, "live_low_ammo")
    supply(3, 20)
    -- A free-transfer reload dip that recovers stays silent.
    ammo_state = {}
    supply(10, 20) -- 30/100.
    supply(0, 20, true) -- The magazine empties for a free refill: 20/100 while reloading.
    supply(10, 20, true)
    supply(10, 20) -- Back to 30: compared with 30, no crossing.
    assert(ammo_state.reserve_outcome ~= "threshold crossed")
    supply(5, 20)
    supply(4, 20, false, "live_low_ammo") -- A real crossing afterwards still warns once.
    supply(4, 20)
    -- A dip that doesn't recover is genuine supply loss: it warns once after the reload.
    ammo_state = {}
    supply(10, 20)
    supply(0, 20, true)
    supply(0, 20, false, "live_low_ammo") -- Reload interrupted at 20/100.
    supply(0, 20)
    -- A pickup during a reload lifts the total: nothing to reconcile.
    ammo_state = {}
    supply(5, 20)
    supply(4, 20, true)
    supply(4, 60, true)
    supply(10, 54)
    -- 0.9.3: ammunition gained during a reload raises the held baseline. Stable 24,
    -- refilled to 25 while reloading, a shot back to 24 in the sample the reload ends.
    ammo_state = {}
    supply(5, 20)
    supply(4, 20, false, "live_low_ammo")
    supply(4, 20, true)
    supply(5, 20, true) -- One round gained mid-reload (pickup, on-kill ammo talent).
    supply(4, 20, false, "live_low_ammo") -- 25 -> 24: a real crossing, as without the reload.
    supply(4, 20)
    supply(4, 20, true) -- A gain that stays below the threshold: no rearm, no duplicate.
    supply(4, 20, false)
    supply(3, 20, true)
    supply(4, 20, true)
    supply(3, 20, false)
    -- A weapon change during a reload starts a fresh, silent baseline.
    ammo_state = {}
    supply(5, 20)
    supply(4, 20, true)
    ammo_state.template = {} -- As if another weapon template were now wielded.
    supply(4, 20, false)
    ammo_state = {}
    slot.max_mag, slot.max_reserve = saved[1], saved[2]
    print("PASS: H1 AMMO LOW crossing reconciled after an immediate reload; plain crossing, recovering free-reload dip, interrupted dip, pickup, mid-reload gain then shot (0.9.3), weapon change and no duplicates")
end

local toughness_state = {}
local toughness = {
    maximum = 100, remaining = 100,
    max_toughness = function(self) return self.maximum end,
    remaining_toughness = function(self) return self.remaining end,
}
local function tough(remaining, expected, broken, recovery, low)
    toughness.remaining = remaining
    local result = Gameplay.toughness(toughness_state, toughness, 25, recovery or 50, low ~= false, broken == true)
    assert(result == expected, tostring(remaining) .. ": " .. tostring(result))
end
tough(10) -- Already low on join.
tough(25)
tough(24)
tough(50)
tough(24) -- Equality at recovery doesn't rearm.
tough(51)
tough(25) -- Equality at the warning threshold is still armed.
tough(24, "live_toughness")
tough(10)
tough(0, "live_broken", true)
tough(0, nil, true)
tough(100)
tough(0, "live_broken", true)
tough(100)
tough(0, "live_toughness") -- Default break toggle is off.
tough(100)
tough(0, "live_broken", true, nil, false) -- Break works independently.
tough(100)
-- The server keeps toughness damage when the maximum rises, so remaining rises too.
toughness.maximum = 500
tough(500) -- Capacity changes alone do not generate a low warning.
tough(300)
tough(100, "live_toughness")
tough(500)
-- v0.3.0 skipped any sample whose maximum changed, losing this crossing.
toughness.maximum = 520
tough(100, "live_toughness")
assert(toughness_state.max_changes == 2 and toughness_state.sample == "crossed below threshold")
assert(Gameplay.toughness(toughness_state, {}, 25, 50, true, true) == nil)
assert(toughness_state.sample == "invalid toughness values")
assert(Gameplay.toughness(toughness_state, nil, 25, 50, true, true) == nil)
assert(toughness_state.sample == "toughness extension unavailable" and not toughness_state.available)
tough(0, nil, true) -- Returning after a missing sample is silent.
toughness_state = {}
toughness.maximum = 100
tough(100, nil, false, 10)
tough(24, "live_toughness", false, 10)
tough(26, nil, false, 10)
tough(24, nil, false, 10) -- Invalid recovery is raised to at least warning + 1.
tough(27, nil, false, 10)
tough(24, "live_toughness", false, 10)
assert(Gameplay.select("live_low_mag", nil, nil, nil, true, "live_toughness") == "live_toughness")
assert(Gameplay.select(nil, "live_task", nil, nil, false, "live_broken") == "live_task")
assert(Gameplay.select("live_toughness", nil, nil, nil, true, "live_broken") == "live_broken")
print("PASS: toughness thresholds, recovery, depletion, independent toggles, capacity, and missing extension")

-- Combat ability readiness, blitz charges and the Arbites dog command.
local new_ability_extension = dofile("tests/ability_stub.lua")
local ability_state = {}
local combat = {name = "veteran_combat_ability", charges = 1, max = 1, can_use = true}
local grenade = {name = "veteran_frag_grenade", charges = 3, max = 3}
local ext = new_ability_extension(combat, grenade)
local function step(expected_ability, expected_blitz, toggles)
    toggles = toggles or {}
    local ability, blitz = Gameplay.abilities(ability_state, ext, toggles.ability ~= false,
        toggles.blitz ~= false, toggles.dog ~= false)
    local blitz_text = blitz and (blitz.key .. ":" .. blitz.kind .. "+" .. blitz.gain)
    assert(ability == expected_ability and blitz_text == expected_blitz, ("ability %s (%s), blitz %s (%s)"):format(
        tostring(ability), tostring(ability_state.combat_status), tostring(blitz_text), tostring(ability_state.blitz_status)))
end
step() -- Spawn with a ready ability and full grenades: silent baseline.
combat.charges, combat.can_use = 0, false
step() -- Used.
combat.progress, combat.paused = 1, true
step() -- A full-looking but paused cooldown with no charge is not ready.
combat.charges, combat.can_use, combat.paused = 1, true, false
step("live_ability")
step() -- Stays ready: no repeat.
combat.can_use = false
step()
combat.can_use = true
step() -- can_use flicker (locked while active, free-use buffs) doesn't re-alert.
combat.charges, combat.can_use = 0, true
step() -- A free-use buff makes can_use true without a charge: not "ready".
combat.charges = 1
step("live_ability")
-- Multi-charge: only the empty-to-usable transition alerts.
combat.max, combat.charges = 2, 2
step()
combat.charges = 1
step()
combat.charges = 0
step()
combat.charges = 1
step("live_ability")
combat.charges = 2
step() -- 1 -> 2 while already ready.
-- A disabled slot reads as zero charges; keep the baseline instead.
combat.enabled = false
step()
assert(ability_state.combat_status == "disabled (baseline kept)")
combat.enabled = nil
step()
-- Toggle off still tracks state, so re-enabling never alerts retroactively.
combat.charges = 0
step()
combat.charges = 1
step(nil, nil, {ability = false})
step()
-- A changed ability (different talent) is a silent baseline.
combat.name, combat.charges = "veteran_stealth", 0
step()
combat.charges = 1
step("live_ability")
-- An ability without charges falls back to can_use_ability.
combat.uses, combat.can_use = false, false
step()
combat.can_use = true
step("live_ability")
combat.uses = nil

-- Grenades: every gain counts for small pools; simultaneous gains combine.
grenade.charges = 1
step()
grenade.charges = 2
step(nil, "live_blitz:grenade+1")
grenade.charges = 0
step()
grenade.charges = 2
step(nil, "live_blitz:grenade+2") -- Two charges in one sample: one notice.
step() -- Same transition sampled again: no duplicate.
grenade.charges = 3
step(nil, "live_blitz:grenade+1", {ability = false}) -- Independent of the ability toggle.
grenade.charges = 2
step()
grenade.charges = 3
step(nil, nil, {blitz = false})
-- Assail: ten regenerating knives only alert when refilled from empty.
grenade.name, grenade.charges, grenade.max = "psyker_throwing_knives", 10, 10
step()
grenade.charges = 4
step()
grenade.charges = 5
step()
grenade.charges = 0
step()
grenade.charges = 1
step(nil, "live_blitz:blitz+1")
-- Smite and Chain Lightning have no charge count: never alert.
grenade.name, grenade.charges, grenade.max = "psyker_smite", 0, 0
step()
assert(ability_state.blitz_status:find("no charge count", 1, true))
-- The Arbites whistle is the dog command: its own key and toggle, from empty only.
grenade.name, grenade.charges, grenade.max = "adamant_whistle", 2, 2
step()
grenade.charges = 1
step()
grenade.charges = 2
step() -- Already had a usable command.
grenade.charges = 0
step()
grenade.charges = 1
step(nil, "live_dog:dog+1", {blitz = false})
grenade.charges = 0
step()
grenade.charges = 1
step(nil, nil, {dog = false})
assert(Gameplay.blitz_kind("ogryn_grenade_friend_rock") == "grenade" and Gameplay.blitz_kind("adamant_shock_mine") == "grenade"
    and Gameplay.blitz_kind("zealot_throwing_knives") == "blitz" and Gameplay.blitz_kind("broker_missile_launcher") == "blitz")
-- A new extension (respawn, hot join, new mission) baselines silently even when charges differ.
grenade.name, grenade.charges, grenade.max = "veteran_frag_grenade", 3, 3
ext = new_ability_extension(combat, grenade)
combat.charges = 0
step()
-- Missing or broken interfaces never raise.
assert(Gameplay.abilities(ability_state, nil, true, true, true) == nil)
assert(ability_state.combat_status == "ability extension unavailable" and not ability_state.available)
ext = {ability_is_equipped = function() return true end}
step()
assert(ability_state.combat_status:find("unreadable", 1, true) and ability_state.blitz_status:find("unreadable", 1, true))
ext = new_ability_extension(combat, {name = "veteran_frag_grenade", equipped = false, charges = 0, max = 0})
step()
assert(ability_state.blitz_status == "not equipped (baseline kept)")
-- Priorities: ability and blitz never interrupt TASK, toughness or ammo, and wait their turn.
assert(Gameplay.select(nil, nil, nil, nil, false, nil, "live_ability") == "live_ability")
assert(Gameplay.select("live_low_ammo", nil, nil, nil, false, nil, "live_ability") == nil)
assert(Gameplay.select("live_ability", nil, "live_low_mag", nil, false, nil, nil) == "live_low_mag")
assert(Gameplay.select("live_ability", "live_task", nil, nil, false, nil, "live_blitz") == "live_task")
assert(Gameplay.select("live_blitz", nil, nil, nil, false, nil, "live_ability") == "live_ability")
assert(Gameplay.select("live_ability", nil, nil, nil, false, nil, "live_blitz") == nil)
assert(Gameplay.select("live_ability", nil, nil, nil, false, "live_toughness", "live_dog") == "live_toughness")
print("PASS: ability readiness, pauses, multi-charge, blitz gains, Assail, Smite, dog command, baselines and priorities")

-- 0.6.0: peril and heat are gone; TASK still outranks everything that remains.
assert(Gameplay.peril_heat == nil and Gameplay.acknowledge_heat == nil)
for key in pairs(Gameplay.priority) do
    assert(not key:find("peril", 1, true) and not key:find("heat", 1, true), key)
    assert(key == "live_task" or Gameplay.priority[key] < Gameplay.priority.live_task, key)
end
assert(Gameplay.select("live_broken", "live_task", nil, nil, false, nil) == "live_task")
assert(Gameplay.select("live_task", "live_task", nil, nil, false, nil) == "live_task")
assert(Gameplay.select("live_task", nil, nil, nil, false, "live_broken") == nil)
print("PASS: peril and heat removed; TASK priority preserved")

-- Pickup markers: read-only post-hooks on the two interaction classes that restore grenades.
for _, path in ipairs({"scripts/extension_systems/interaction/interactions/grenade_interaction",
    "scripts/extension_systems/interaction/interactions/ammunition_interaction"}) do
    local class = {stop = function() end}
    mod.require_callbacks[path](class)
    mod.require_callbacks[path](class) -- Repeated require: hooked once.
end
assert(#mod.pickup_hooks == 2)
local picker = {}
mod.pickup_hooks[1].callback({}, nil, picker, {}, 0, "success")
mod.pickup_hooks[2].callback({}, nil, picker, {}, 0, "interaction_cancelled")
assert(Gameplay.pickup_count(picker) == 1 and Gameplay.pickup_count({}) == 0 and Gameplay.pickup_count(nil) == 0)
-- M6 (0.9.2/0.9.3 audits): ordinary ammunition clips count only when the
-- player's talents let ammunition refill the blitz (vanilla
-- _can_refill_grenades: disable_grenade_pickups + ammo_pickups_refills_grenades,
-- Zealot Throwing Knives); crates and unreadable data still count.
do
    local rules = {}
    ScriptUnit = {has_extension = function(unit, system)
        assert(system == "talent_system")
        return unit == picker and {has_special_rule = function(_, name) return rules[name] end} or nil
    end}
    local units = {}
    local function pickup_unit(name)
        local target = {}
        units[target] = name
        return {target_unit = target}
    end
    Unit = {alive = function(target) return units[target] ~= nil end,
        get_data = function(target, key) assert(key == "pickup_type"); return units[target] end}
    local ammo_hook, grenade_hook = mod.pickup_hooks[2].callback, mod.pickup_hooks[1].callback
    local function count(hook, component)
        local before = Gameplay.pickup_count(picker)
        hook({}, nil, picker, component, 0, "success")
        return Gameplay.pickup_count(picker) - before
    end
    assert(count(ammo_hook, pickup_unit("small_clip")) == 0) -- No talent: a clip restores no blitz.
    assert(count(ammo_hook, pickup_unit("large_clip")) == 0)
    rules.ammo_pickups_refills_grenades = true -- Only one of vanilla's pair: still no refill.
    assert(count(ammo_hook, pickup_unit("small_clip")) == 0)
    rules.disable_grenade_pickups = true -- Throwing Knives: clips refill knives.
    assert(count(ammo_hook, pickup_unit("small_clip")) == 1 and count(ammo_hook, pickup_unit("large_clip")) == 1)
    assert(Gameplay.talents_refill_blitz(picker) == true)
    rules = {}
    assert(Gameplay.talents_refill_blitz(picker) == false and Gameplay.talents_refill_blitz({}) == nil)
    local other = {}
    local before = Gameplay.pickup_count(other)
    ammo_hook({}, nil, other, pickup_unit("small_clip"), 0, "success") -- Talents unreadable: as before.
    assert(Gameplay.pickup_count(other) == before + 1)
    assert(count(ammo_hook, pickup_unit("ammo_cache_deployable")) == 1) -- Crates may restore grenades.
    assert(count(ammo_hook, {target_unit = {}}) == 1) -- Despawned or unknown target: as before.
    assert(count(ammo_hook, {}) == 1 and count(ammo_hook, nil) == 1)
    assert(count(grenade_hook, pickup_unit("small_grenade")) == 1)
    assert(count(grenade_hook, pickup_unit("small_clip")) == 1) -- The grenade interaction always counts.
    Unit = {alive = function() error("broken") end}
    assert(count(ammo_hook, pickup_unit("small_clip")) == 1) -- Unreadable: keep the old protection.
    Unit = nil
    assert(count(ammo_hook, pickup_unit("small_clip")) == 1)
    ScriptUnit = nil
end
print("PASS: pickup markers count only successful grenade and ammunition pickups; ordinary clips (M6) don't count")

-- Stimms: the running buff's own duration and progress, once per cycle.
do
    local buffs = dofile("tests/stimm_stub.lua")()
    local templates = buffs.templates
    local state = {}
    local function at(now, expected, threshold, enabled)
        buffs.now = now
        local alert = Gameplay.stimm(state, buffs, threshold or 3, enabled ~= false)
        assert(alert == expected, ("%s: expected %s, got %s (%s)"):format(now, tostring(expected),
            tostring(alert), tostring(state.status)))
    end
    assert(Gameplay.stimm(state, nil, 3, true) == nil and state.status == "buff extension unavailable")
    assert(Gameplay.stimm(state, {buffs = function() error("boom") end}, 3, true) == nil
        and state.status:find("unreadable", 1, true))
    assert(Gameplay.stimm(state, {buffs = function() return nil end}, 3, true) == nil)
    -- Holding a stimm, Stimm Supply, the heal stimm and stimm talent buffs are not timed stimm effects.
    buffs:add(templates.field)
    buffs:add(templates.heal)
    buffs:add(templates.talent)
    at(0, nil)
    assert(state.status == "no active stimm")
    -- Hive Scum stimm: nothing during the effect, one warning at three seconds left.
    buffs:add(templates.broker)
    at(0.1)
    assert(state.status == "active, armed" and math.abs(state.remaining - 14.9) < 1e-9)
    at(6)
    at(11.9) -- 3.1 left.
    at(12, "live_stimm") -- 3.0 left: at or below the threshold.
    at(12.1)
    at(14.9)
    at(15.1) -- Finished: excluded before vanilla removes it.
    buffs:remove_finished()
    at(15.2)
    assert(state.status == "no active stimm" and state.remaining == nil)
    -- Stimm Lab duration: 15 + 5 via add_duration, warns at 17 seconds in.
    buffs.now = 20
    buffs:add(templates.broker, 5)
    at(20)
    at(36.9)
    at(37, "live_stimm")
    -- Extension inside the threshold rearms and warns again; a small correction doesn't.
    buffs.list[#buffs.list]:add_duration(4) -- 2 left + 4 = 6.
    at(38)
    assert(state.status == "extended, rearmed")
    at(41, "live_stimm")
    buffs.list[#buffs.list]:set_start_time(20.5) -- Server correction: 2.9 -> 3.5 left.
    at(41.1)
    assert(state.armed == false)
    at(42)
    -- Reinjection replaces the instance (unique_buff_id) and starts a new cycle.
    buffs.now = 43
    buffs:add(templates.power)
    at(43)
    at(55, "live_stimm")
    -- Joining or first sampling inside the threshold stays silent.
    state = {}
    at(56)
    assert(state.status == "active inside threshold (silent)")
    at(57.5)
    -- Toggle off at the crossing disarms; turning it back on can't replay it.
    buffs.now = 60
    buffs:add(templates.broker)
    at(60, nil, 3, false)
    at(72, nil, 3, false)
    at(72.1)
    -- Threshold changes re-baseline; the range is clamped to 1-10 seconds.
    buffs.now = 80
    buffs:add(templates.broker)
    at(80, nil, 10)
    at(85, "live_stimm", 10)
    at(85.1, nil, 3)
    assert(state.status == "threshold changed" and state.armed)
    at(92, "live_stimm", 3)
    buffs.now = 100
    buffs:add(templates.broker)
    at(100, nil, 50)
    assert(state.threshold == 10)
    at(100.1, nil, 0)
    assert(state.threshold == 1)
    at(113.9, nil, 0)
    at(114, "live_stimm", 0)
    -- Invalid buff data is ignored rather than guessed.
    local bad = buffs:add({name = "syringe_broker_buff", unique_buff_id = "syringe_stimm"})
    at(115)
    assert(state.status == "ended")
    bad.extra = 0 / 0
    at(115.1)
    bad.extra = math.huge
    at(115.2)
    assert(state.remaining == nil)
    -- Priorities: TASK and toughness first, STIM interrupts ammo and resources at once.
    assert(Gameplay.priority.live_stimm < Gameplay.priority.live_toughness
        and Gameplay.priority.live_stimm > Gameplay.priority.live_low_mag)
    assert(Gameplay.select(nil, nil, "live_low_mag", "live_low_ammo", false, nil, "live_ability", "live_stimm") == "live_stimm")
    assert(Gameplay.select("live_low_mag", nil, nil, nil, true, nil, nil, "live_stimm") == "live_stimm")
    assert(Gameplay.select("live_toughness", nil, nil, nil, false, nil, nil, "live_stimm") == nil)
    assert(Gameplay.select(nil, nil, nil, nil, false, "live_toughness", nil, "live_stimm") == "live_toughness")
    assert(Gameplay.select("live_stimm", "live_task", nil, nil, false, nil, nil, "live_stimm") == "live_task")
    assert(Gameplay.select("live_stimm", nil, "live_low_mag", nil, false, nil, "live_ability") == nil)
    print("PASS: stimm buff reads, Stimm Lab duration, one warning per cycle, extension, correction, reinjection, invalid data and priorities")
end

-- Exercise the actual HUD with live alerts enabled and synthetic previews disabled.
Managers = {state = {extension = manager}}
mod.reset_icons(mod.new_simple_assets(), true) -- Timelines run with the approved icons loaded.
mod:test_live_hud(a, map, components, slot)
mod:test_ammo_timelines(a, map, components, slot, template)
mod:test_ability_timeline(a, map, components, slot, template)
mod:test_style_timeline(a, map, components, slot, template)
mod:test_stimm_timeline(a, map, components, slot, template)
mod:test_icon_modes(a, map, components, slot, template)
mod:test_audit_regressions(a, map, components, slot, template)
mod:test_queue_accounting(a, map, components, slot, template)
mod:test_texture_lifecycle(a, map, components, slot, template)
-- The same lifecycles and priorities in the other two display modes.
for _, mode in ipairs({"text", "icon"}) do
    mod:set_setting("alert_display", mode)
    mod:test_ammo_timelines(a, map, components, slot, template)
    mod:test_style_timeline(a, map, components, slot, template)
    mod:test_stimm_timeline(a, map, components, slot, template)
end
mod:set_setting("alert_display", "icon_text")
print("PASS: ammo, styling and stimm timelines repeated in Text only and Icon only modes")
