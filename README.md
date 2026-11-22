# Darktide Crosshair Alerts

Development build 0.9.6-dev for Darktide Mod Framework. Mod Options provides separate toggles for reticle replacement, synthetic previews, and each live alert.

The dot defaults to cyan and 6 UI units (your saved pink-purple colour is kept). Vanilla uses 4. Crosshair replacement is dot-first (0.6.1). Every reticle vanilla resolves becomes the custom dot, in hip fire, while braced and in alternate-fire spread modes: `assault`, `bfg`, `cross`, `flamer`, `shotgun`, `shotgun_wide`, `spray_n_pray`, `dot_special` and any type added by a future patch. These draw only spread segments plus hit markers, and the dot template draws the same hit markers. Five types are kept because they carry information the dot can't show or mean "no reticle": `ironsight` (genuine ADS, no reticle by design), `charge_up` (staff charge bars, with its centre restyled as your dot), `charge_up_ads` (Helbore charge bars while aiming), `projectile_drop` (the drop ladder for arcing projectiles on the gauntlet and Rumbler), and `none` (reloads and similar). A vanilla dot is hidden only while the weapon's alternate fire is a true sight. Turning **Replace ordinary crosshairs** off restores every vanilla reticle.

The notification uses one compact HUD widget anchored below screen centre. It shows an icon and text, an icon or text only (see **Alert icons and display mode**). Fresh installs default to vivid yellow (#FFF56B), bold text with a four-direction dark outline, and an offset of 60 UI units below centre. Alerts appear at full opacity and 125% text size, settle over 180 ms, then fade out over their final 180 ms. TASK defaults to size 26 for 5 seconds. LOW MAG and LOW AMMO default to size 23 for 2.5 seconds each. Configure their durations separately in Mod Options. Saved colour, shared text size, offset and preview duration remain in place on upgrade. Set notification colour to #FFF56B and text size to 23 individually if you want the new appearance on an existing install. A new preview replaces the previous one in the same spot. The allowed modes are standard co-op missions and the Psykhanium shooting range. The HUD requires a living, controllable player unit and clears the preview when it detects a player-unit change or the mod is disabled.

## Live alerts

- **TASK** appears once when a data interrogator is interrupted and awaiting a restart. The same interruption stays recorded while someone works on the minigame. A subsequent interruption can alert after decoding resumes. Hot-joining an actionable stall counts as one alert. Devices that finish or that have only reached initial setup do not alert.
- **LOW MAG** and **LOW AMMO** use the currently wielded ranged weapon, with fresh defaults of 20% magazine and 25% total ammunition. LOW MAG shows **RELOAD** when the magazine drops to or below its threshold, so a five-round cylinder at 20% warns on its last round and not again at zero. **Small magazine warning** (default one round) also treats that many rounds as low for magazines of three or more; 0 turns it off. A full magazine is never low. Since 0.6.2, weapons whose maximum magazine is one or two rounds (double-barrelled shotguns, single-shot launchers) never show RELOAD; this depends only on capacity, so a larger magazine down to one or two rounds still warns. LOW AMMO shows **AMMO LOW** when the weapon's total ammunition, magazine plus reserve, drops strictly below its threshold on a shot. 0.6.1 and earlier measured reserve alone (see below). Weapons with no reserve never show AMMO LOW. Both counts aggregate only the clips in use. Starting a mission, equipping a different weapon or changing a threshold establishes a baseline. Reloading or picking up enough ammunition to reach the threshold rearms the appropriate alert. Carrying an objective item preserves the last ranged baseline. A drop across the threshold can be detected on the first usable sample after re-equipping. Equipping an already-low weapon by itself stays silent.
- **Alert styling.** LOW MAG shows a fixed **RELOAD** in amber, with no round count (0.6.2). LOW AMMO shows **AMMO LOW** in red, so the two differ in text as well as colour (and in icon from 0.9.0). The 0.6.2–0.9.0 red underline under AMMO LOW is removed in 0.9.1. TOUGHNESS is cyan, BROKEN red, ABILITY READY warm golden yellow (#FFD628, 0.9.1; soft green before), DOG READY lavender, STIM lime, GRENADE and BLITZ light grey. TASK and previews keep your **Notification colour** (default bright yellow #FFF56B). **Colour alerts by category** under Appearance (on by default) turns this off, so every alert uses Notification colour. The category colour tints the alert's icon as well as its text.
- The HUD draws one message. Priority is TASK, BROKEN, TOUGHNESS, STIM, MAG, AMMO, ABILITY READY, DOG READY, then GRENADE or BLITZ. TASK and toughness can interrupt ammo immediately. Toughness is time-sensitive, so a crossing blocked by TASK is dropped without a delayed warning. Ammo alerts get one second of visibility before another ammo alert can replace them. One pending crossing per ammo type can wait for up to 10 seconds. Interrupted LOW AMMO can resume for its remaining display time within that original window. Ammo warnings are hidden while the ranged weapon is stowed. Since 0.6.2, a waiting AMMO LOW's 10 seconds only count while the ranged weapon is out, so it appears when you draw the weapon again if the supply is still low. Returning to the same weapon reconciles current counts. A different weapon, player reset, recovery above the low range, or a changed threshold discards the corresponding pending warning.

## Abilities & Blitz

- **ABILITY READY** appears when the combat ability goes from no usable charge to at least one. It follows the synced charge count (`remaining_ability_charges`), as the vanilla ability icon does. A paused cooldown that looks full, a free-use buff or a locked-while-active state doesn't count. Multi-charge abilities alert only on the empty-to-usable step, not on 1 to 2. Abilities without charges fall back to `can_use_ability()`.
- **GRENADE +N** or **BLITZ +N** appears when blitz charges increase. Gains in the same 100 ms sample combine, and a further gain of the same kind while the notice is visible updates it (GRENADE +2) instead of adding another. Pools larger than four, such as Assail's ten knives, alert only when refilled from empty. Smite and Chain Lightning have no charge count and never alert. Your own grenade and ammunition-crate pickups stay silent: a read-only post-hook on the client-side `stop()` of `GrenadeInteraction` and `AmmunitionInteraction` records a successful pickup, and a blitz gain within two seconds of it is treated as the pickup. A talent regeneration inside that window is also silent. Ordinary ammunition clips (`small_clip`, `large_clip`) count only when your talents let ammunition refill the blitz, as vanilla checks it (the `disable_grenade_pickups` + `ammo_pickups_refills_grenades` special rules of Zealot Throwing Knives). A crate, or a pickup whose type or talents can't be read, still counts. Each such pickup explains at most one gain within its own two seconds (0.9.4: credits expire independently, oldest first, and any charge increase uses one even when it earns no notice), so a regeneration later still notifies. Another player's pickup doesn't affect yours.
- **DOG READY** is for the Arbites whistle (Remote Detonation), which is the `adamant_whistle` blitz with two charges and a 50-second cooldown. It appears when the whistle regains a charge from empty, under its own toggle, and never as GRENADE or BLITZ. Ordinary dog targeting through tags has no cooldown or charge exposed to the client, so it never alerts.
- These notices rank below TASK, toughness and ammunition. They never interrupt another alert. One notice can wait up to four seconds in a single slot and is dropped if it expires, the ability is used again, or its toggle is turned off. Spawning, respawning, hot-joining, changing ability and returning from a disable all start a silent baseline, except that a charge regained while netted or downed shows on release.
- Duration is shared: **Ability and blitz duration (seconds)**, default 2.

## Alert icons and display mode (0.9.0)

- **Alert display mode** under Appearance: **Icon + text** (default), **Icon only** or **Text only**. Timing, priorities, durations, fade and pop are the same in every mode.
- Icons are the approved HUD icon pack artwork, shipped as transparent PNGs in `assets/icons/64` and `assets/icons/128`: TASK objective, RELOAD magazine, AMMO LOW low ammunition, TOUGHNESS shield, BROKEN broken shield, ABILITY READY ability ready (the lightning bolt since 0.9.1; 0.9.0 had a four-point starburst), GRENADE and BLITZ grenade, DOG READY dog command, STIM stimulant.
- **They need the optional [Simple Assets](https://www.nexusmods.com/warhammer40kdarktide/mods/1008) mod (2.0.x).** Once all mods have loaded, Crosshair Alerts asks Simple Assets for all 18 PNGs in a single request. Simple Assets serves them to vanilla's `Managers.url_loader`, and the HUD draws them with the default UI material (`ui_default_base`, `material_values.texture_map`) tinted in the category colour, with a dark 1.5-unit outline like the text. The textures are cached and reused across HUDs and missions and never reloaded per frame. Since 0.9.5 they are released when the mod unloads (a developer reload or game exit), and a failed file is retried a bounded number of times (see below).
- The icon is 28 UI units at the default text size and scales with the text and its pop (TASK is slightly larger). The 64 px export is used unless the icon is drawn larger than 64 screen pixels (for example 4K), where the 128 px export is used.
- In Icon + text the icon sits left of the text and the pair stays centred. In Icon only the icon is centred. Previews (TEST ALERT, TEST WARNING) have no category and stay text in every mode.
- **Fallback:** without Simple Assets, while the icons are still loading, if Simple Assets fails, or if an icon's files are missing, that alert shows its text exactly as in Text only. A missing 64 px or 128 px file falls back to the other export. Nothing is drawn without a loaded texture.
- 0.8.x drew rectangle-and-circle symbols; those are removed.
- 0.9.1 changes only visuals: the ABILITY READY artwork and colour, and no AMMO LOW underline in any mode.

## 0.9.2 audit fixes

No thresholds, priorities, timings, settings or visuals change.

- **AMMO LOW across a reload.** A reload keeps the last stable total as the baseline. A shot that crosses 25% in the same sample as a reload starting now warns once when the reload ends. A free-transfer dip that recovers by then stays silent.
- **Waiting ability and blitz notices** are checked against the current state before new events are offered and before they compete for the screen. A GRENADE +N whose charge was thrown meanwhile is dropped or reduced. An ABILITY READY whose ability was used again is dropped. A stale notice no longer discards a newer valid one. While the ability extension or slot can't be read (missing, disabled), the notice waits and still expires, but never shows on old data.
- **A waiting STIM** is dropped when an extension lifts the stimm back out of the warning range (threshold plus the one-second margin). Only a new crossing warns again. A STIM already on screen finishes as before.
- **A waiting RELOAD** is held while the player is reloading. A reload that refills the magazine cancels it, an interrupted one lets it show while it is still valid, and the RELOAD shown at the crossing is unchanged.
- `/dca_ability` diagnostics show a valid `false` (usable, paused) instead of `nil`.

## 0.9.3 review corrections

No thresholds, priorities, timings, settings or visuals change.

- **Unreadable notices are parked.** A waiting ABILITY READY whose slot can't be read is set aside with its own expiry. It no longer makes a fresh GRENADE +N wait or be dropped, and it rejoins once the slot reads and still validates.
- **Ability identity.** A waiting ABILITY READY belongs to the ability (`ability_name`) and ability extension it was queued for. Another ability that is already ready never shows it, including after a missing or unreadable sample.
- **Throwing Knives.** Ordinary clips explain a blitz gain only with the vanilla ammunition-refill talent rules. Each pickup explains one gain. The two-second window is unchanged.
- **AMMO LOW.** Ammunition gained during a reload raises the held baseline, so a shot that takes it back under 25% when the reload ends still warns once.
- **STIM.** A genuine extension (`Buff.add_duration` raises `duration()`) that lifts a waiting STIM out of the warning window drops it and rearms, so the fresh crossing warns once. Start-time corrections don't change `duration()` and keep the one-second margin. A STIM already on screen finishes as before.

## 0.9.4 queue and pickup accounting

No thresholds, priorities, timings, settings or visuals change.

- **One waiting queue.** Waiting ability and blitz notices share one bounded queue, at most one per alert. A notice is dropped only by its own checks (expiry, toggle, identity, spent charge) or by a checked notice of higher priority. A notice that can't be checked this sample (unreadable slot, missing extension) keeps its deadline but neither evicts nor is evicted. A new gain for a waiting GRENADE merges into it (GRENADE +2, deadline refreshed), so a returning notice never overwrites newer information.
- **Independent pickup credits.** Each counted pickup has its own two-second credit. A later pickup never extends an earlier one. Any blitz charge increase uses the oldest live credit, even one that earns no notice (Throwing Knives 1 → 3), so it can't later silence a real regeneration.

## Stimm expiration (0.7.0)

- **STIM 3s** appears once, for at most two seconds, when an active stimm effect has your threshold or less left (default 3 seconds, configurable 1-10 under **Stimm**). Nothing is shown during the rest of the effect, and there is no timer, icon or bar.
- It reads the running buff on your own buff extension, never the injection animation, the pocketable or the ability cooldown. Covered: the Hive Scum stimm (`syringe_broker_buff`, 15 s plus Stimm Lab's `syringe_duration` bonus, which vanilla applies with `Buff.add_duration`) and picked-up combat stimms (power, speed and ability, 15 s). All share `unique_buff_id = "syringe_stimm"`, so a new injection replaces the running one. Remaining time is `duration() * duration_progress()`, the same values the vanilla buff bar uses, which include extensions and server start-time corrections.
- A new injection starts a new cycle. An extension rearms only when it lifts the remaining time more than one second above the threshold, so small corrections near the threshold can't warn twice. First seeing a stimm already inside the threshold (joining, respawn, new mission) stays silent.
- TASK and toughness take precedence; STIM interrupts ammo and ability notices at once. A STIM held back by TASK or toughness shows the real remaining time when it appears (for example **STIM 2s**), and is dropped if the effect has ended. An on-screen STIM disappears as soon as the effect ends or is replaced.
- Not covered: Stimm Supply (`*_stimm_field` buffs have no duration; they last while you stand in the field) and the corruption-heal stimm (no shared stimm id, healing over time rather than a combat effect).

## Toughness and Mod Options

- **TOUGHNESS** is enabled by default. It appears for 2.5 seconds when the local player's toughness drops below **25%**. A second warning requires recovery strictly above **50%**. Both percentages are configurable. The effective recovery threshold is always at least one percentage point above the warning threshold. An already-low starting value establishes a silent baseline. Changes in maximum toughness no longer reset detection. Being netted, pounced or downed keeps the baseline, so a drop during a disable is reported on release.
- **BROKEN** is independently configurable and off by default. It appears for 2.5 seconds when a valid positive sample is followed by zero. If the same sample crosses both thresholds, only BROKEN is eligible. These warnings indicate toughness state. They do not predict attack timing.
- Mod Options is grouped under **Crosshair**, **Appearance**, **Mission Alerts**, **Ammunition**, **Toughness**, **Abilities & Blitz**, **Stimm**, and **Testing & Diagnostics**. Native DMF checkbox children hide their controls when disabled. Existing settings retain their IDs and defaults, including preview duration under Testing & Diagnostics. 0.3.1 added **Small magazine warning (rounds)** under LOW MAG and **Enable on-demand toughness diagnostics**. 0.4.0 added **Abilities & Blitz** and ability diagnostics. 0.5.x had a Peril & Heat group; 0.6.0 removes it because the vanilla peril and plasma heat warnings are already prominent. Its saved values are simply ignored. 0.6.0 adds **Colour alerts by category** under Appearance. 0.8.0 adds **Alert display mode** under Appearance; 0.9.0 keeps it and draws the approved icons. 0.7.0 adds a **Stimm** group (one toggle and its threshold) before Testing & Diagnostics. The established outline and entrance animation use the same rendering code.

## 0.9.5 texture lifecycle

Only icon loading changes; gameplay detection, priorities, colours, timings, positions and settings are as in 0.9.4.

- **Bounded retries.** Vanilla's URL loader caches a failed texture and keeps rejecting that URL until its reference count returns to 0. Crosshair Alerts now gives each failed URL's reference back as soon as the failure arrives, then retries only the files that failed: at most three attempts per file, 5 seconds and then 30 seconds of HUD time apart. Icons that loaded are kept and drawn meanwhile. A file still failing after the third attempt stays as text (or uses its other export) until the mod is reloaded. There is no background loop: the HUD checks one field per frame, and loading starts only when a retry is due.
- **Reference ownership.** Every URL-loader reference the mod receives through Simple Assets is counted and given back exactly once. Loaded textures are kept across HUD recreation and missions and released in the mod's `on_unload`, which DMF calls after it has destroyed the HUD element on a developer reload and before game exit. A load that completes after that is given back on arrival and never drawn, so repeated developer reloads hold one reference per file, not one more per reload.

## 0.9.6 texture ownership hardening

From an independent review of 0.9.5. Only icon loading changes.

- **One request per file.** Each icon file is requested from Simple Assets on its own, and its URL-loader reference is counted as soon as its result arrives. A file whose request raises or never settles now costs only that file: the other icons load and draw, retries of other files go ahead, and every reference already received is given back at unload. A file that settles after unload is given back on arrival.
- **References owed at unload.** If the URL loader can't take a reference back during unload, the reference is kept in a DMF persistent table and returned by the next load of the mod, but only to the same loader; a replaced loader has already destroyed its textures, so those references are dropped.
- Retry limits, delays and fallback are unchanged from 0.9.5.

## Install on Fedora

**Icons (optional):** install Simple Assets 2.0.x from Nexus Mods (mod 1008) the usual way. Put its `SimpleAssets` folder in the game's `mods` folder, keeping its `bin/simple-assets-runtime.dll`, and add the line `SimpleAssets` to `mods/mod_load_order.txt`. Its position in the list doesn't matter for Crosshair Alerts, which looks it up after all mods have loaded. Skip this and alerts stay text.

Use the existing working Darktide Mod Loader and DMF setup. For an upgrade from 0.9.5-dev, close Darktide and place the new ZIP in `~/Downloads`. Run the following on Fedora. It backs up the old mod folder outside the game before replacing its files. The existing load order, Simple Assets and DMF settings stay in place; no files need deleting. (Upgrading straight from 0.8.x, also delete `scripts/mods/DarktideCrosshairAlerts/alert_symbols.lua` after the backup.)

```bash
(
  set -e
  game_dir="/run/media/$USER/Games/SteamLibrary/steamapps/common/Warhammer 40,000 DARKTIDE"
  archive="$HOME/Downloads/DarktideCrosshairAlerts-0.9.6-dev.zip"
  mod_dir="$game_dir/mods/DarktideCrosshairAlerts"

  unzip -tq "$archive"
  test -f "$mod_dir/DarktideCrosshairAlerts.mod"
  grep -Fxq 'DarktideCrosshairAlerts' "$game_dir/mods/mod_load_order.txt"
  backup=$(mktemp -d "$HOME/DarktideCrosshairAlerts-0.9.5-dev.XXXXXX")
  cp -a -- "$mod_dir" "$backup/"
  unzip -o "$archive" -d "$game_dir/mods"
  printf 'Previous build saved at %s\n' "$backup/DarktideCrosshairAlerts"
)
```

For a fresh install, use the following procedure. Start with Darktide closed. Transfer `DarktideCrosshairAlerts-0.9.6-dev.zip` to `~/Downloads` on Fedora. Set `game_dir` to the actual Darktide directory if your Steam library differs from the example. This copies only the new mod and backs up the active mod list before editing it.

```bash
(
  set -e
  game_dir="/run/media/$USER/Games/SteamLibrary/steamapps/common/Warhammer 40,000 DARKTIDE"
  archive="$HOME/Downloads/DarktideCrosshairAlerts-0.9.6-dev.zip"
  mod_dir="$game_dir/mods/DarktideCrosshairAlerts"
  load_order="$game_dir/mods/mod_load_order.txt"

  test -f "$archive"
  test -f "$game_dir/mods/dmf/dmf.mod"
  test -f "$load_order"
  test ! -e "$mod_dir" && test ! -L "$mod_dir" || exit 1
  unzip -n "$archive" -d "$game_dir/mods"
  if ! grep -Fxq 'DarktideCrosshairAlerts' "$load_order"; then
    backup=$(mktemp "$load_order.dca-backup.XXXXXX")
    cp -p -- "$load_order" "$backup"
    printf '\nDarktideCrosshairAlerts\n' >> "$load_order"
    printf 'Saved load order backup at %s\n' "$backup"
  fi
)
```

Launch Darktide through Steam as usual. To reverse the install, close the game and remove the line `DarktideCrosshairAlerts` from the active list. Keep the backed-up list and the extracted folder if you want to preserve the test setup.

## Manual playtest

1. In Mod Options, open **Crosshair Alerts**. Check that **Dot opacity (%)** renders without an error and your saved reticle settings are present. Set **Preview brief notification** to a free key. Enter the Psykhanium firing area and press it. Check that the text is readable against bright and dark areas. Check that **TEST ALERT** disappears after the configured duration and stays fixed while firing, strafing and aiming.
2. In a standard co-op mission, type `/dca_preview hold` in chat to show **TEST WARNING**. Use `/dca_preview clear` to dismiss it. `/dca_preview` shows the brief variant. Repeat the preview rapidly to check that there is still only one alert. Check suppression in the hub, while downed and while spectating, and check that the alert does not carry over on respawn.
3. Compare an ordinary melee and ranged weapon, ADS, the Helbore or a Psyker staff, and a weapon with a specialist reticle. Check normal and weakspot hit indicators and charge feedback. Check that braced weapons (Arbites shotpistol and shield, heavy stubber, braced autogun) keep the saved coloured dot while braced, and that a lasgun or autogun ADS shows only its ironsight. Enter the Mourningstar, load into a mission and return to the hub. Check the log for duplicate hook warnings. If you use DMF developer reload, repeat the transitions after a reload.
4. Switch off **Replace ordinary crosshairs** and check vanilla reticles while previews still work. Disable the whole mod while a persistent preview is visible and check that both features stop. Re-enable and verify a fresh preview. If you use another reticle mod, first test this build without its reticle overrides, then test the alerts-only combination.

5. In a standard co-op mission on a regular client, check that initial decoder setup is silent, a stall produces one TASK, starting or cancelling the minigame does not repeat it, and a later stall produces a new TASK. Check late joins while a device is stalled, after completion, and with multiple devices when possible.
6. Fire across the magazine threshold and keep firing until the total (magazine plus reserve) drops below 25%. Check low starting ammo, switching weapons, loading shells individually, ammo pickups, and weapons with a single round, multiple clips, or no ordinary ammo. Verify that TASK preempts an ammo alert and that each toggle works independently.

7. In a mission, let toughness drop from above 25% to below it. Recover to 50% or less and drop again, then recover above 50% and repeat. The second alert should require the higher recovery. Enable **Warn when toughness breaks**, test a positive-to-zero hit and check that a direct break shows only BROKEN when both settings are on. Check an already-low join or respawn, simultaneous ammo warnings, and a decoder stall during combat. Open each Mod Options group and confirm your saved dot colour and that dependent controls hide when toggled off.

## Diagnose ability and blitz alerts

1. Enable **Enable on-demand ability diagnostics** under Testing & Diagnostics.
2. In a mission, run `/dca_ability`. The first line shows, for the combat ability and the blitz: the ability name, charges and maximum, ready state, vanilla's `can_use_ability()`, regeneration progress and whether it is paused, followed by any waiting notice and the latest decision. The second line lists up to five recent decisions, such as **queued ABILITY READY**, **shown GRENADE +1** or **dropped ABILITY READY: expired behind higher alerts**.
3. If an alert is missing or wrong, copy both lines right after the event. Output is one snapshot per command.

## Diagnose a missing TOUGHNESS alert

1. Enable **Warn at low toughness** and **Enable on-demand toughness diagnostics** under Testing & Diagnostics.
2. In a standard co-op mission at full toughness, run `/dca_toughness`. It should report remaining and maximum toughness, the percentage, vanilla's own percentage, the thresholds, **armed**, the number of maximum-toughness changes seen, and the latest decision.
3. Take hits until toughness drops below 25% and run `/dca_toughness` again. The decision should read **emitted TOUGHNESS**, or **dropped TOUGHNESS: TASK visible** if TASK was showing. The second line lists up to five recent state changes. Copy both lines if no alert appeared. A report of **toughness extension unavailable** or **invalid toughness values** means the game interface differs from the inspected source.
4. Output is one snapshot per command. Turn diagnostics off when done.

## Reproduce a missed LOW MAG alert

1. Enable **LOW MAG** and **Enable on-demand magazine diagnostics**. In a mission with a power cell, bring the Huntsman shotgun to three shells and run `/dca_mag`. Confirm the snapshot is armed at your current capacity and threshold.
2. Pick up the cell and let an enemy hit drop it. Switch back to the same shotgun at three shells and fire twice promptly. Then run `/dca_mag` again before firing, reloading or swapping. The command prints a snapshot and up to five recent state changes. Copy both outputs if the warning is missing. If a higher-priority alert is visible, wait for it to clear within the pending window.
3. Repeat once with a short pause after wielding to compare both sample timings. Swap to melee and back while still at one shell to confirm there is no extra warning.

The offline reproduction confirmed that v0.2.2-dev could lose the armed baseline during a sampled `slot_luggable` state. A separate guard also discarded crossings on the first valid ranged sample after an observed swap. These paths are fixed. The exact state timing from the original Fedora session was not captured.

## Diagnose a missing LOW AMMO alert

1. In a standard co-op mission with a conventional ammo-fed ranged weapon, enable **LOW AMMO** and **Enable on-demand ammunition supply diagnostics** in Mod Options.
2. Equip the weapon with plenty of ammunition and run `/dca_reserve`. The first line shows the slot, the total (magazine plus reserve) against its maximum and percentage, the threshold, magazine and reserve separately, armed state, pending time, the displayed alert and the latest outcome. The second line lists up to five recent supply changes. When melee is equipped, counts are labelled as the last ranged sample.
3. Fire until the total drops below the threshold. AMMO LOW should appear on that shot, or right after RELOAD if the same shot crossed both. Reloading moves rounds between magazine and reserve and doesn't change the total, so it never triggers AMMO LOW.
4. Run `/dca_reserve` again. **deferred by higher priority** means a higher alert is visible. **waiting for ranged weapon** means you swapped to melee or picked up an item; draw the weapon to see it. Copy both lines if the warning is still missing. Pick up enough ammunition to rearm, then repeat.
5. Turn diagnostics off when done.

Why 0.6.2 changed this: vanilla magazine reloads first return the remaining rounds to reserve, then refill the magazine from it. Reserve therefore only fell during reloads, so the old crossing always landed mid-reload, right after or behind RELOAD. A reload followed by a swap to melee let the waiting warning expire unseen, and it never repeated while reserve stayed low. Reserve also jumped up by the returned rounds at the start of each reload. The total only falls when you fire.

## Verification and limits

Run `luajit tests/test_mod.lua` or `lua5.1 tests/test_mod.lua` from the repository root. The 0.9.6 suite was run with LuaJIT 2.1. The offline suite exercises the mod entry point, hooks, HUD drawing logic, decoder and ammo snapshots, and priorities with game and DMF stubs.

The HUD samples at most every 100 ms while it has a valid alive player context. It reads the local HUD player's `player_extensions().toughness` from `toughness_system`, then uses `remaining_toughness()` divided by `max_toughness()`. This is the same unrounded ratio as vanilla's `current_toughness_percent()`. The source has a `toughness_broken` attack-result enum. I did not verify a dedicated victim-side HUD event for it, so BROKEN uses a read-only transition instead of adding a damage hook. A break and recovery between samples can be missed. On a client, the local player uses `PlayerHuskToughnessExtension`, which reads maximum toughness and toughness damage from network fields. The server rewrites maximum toughness from buffs every frame. v0.3.0 skipped any sample whose maximum differed, so a buff change at the moment of a hit lost the crossing; a frequently changing maximum would have suppressed every warning. 0.3.1 compares percentages. Because the server keeps damage when the maximum rises and reduces it when the maximum falls, a capacity change alone cannot lower the percentage. It reads `DecoderDeviceSystem:unit_to_extension_map()` through `Managers.state.extension:system("decoder_device_system")`. Decoder state comes from `is_finished()`, `decoding_interrupted()`, and `wait_for_restart()`. A DMF post-hook reads the completion argument of the client's `hot_join_sync` because the inspected implementation receives it without storing it in the extension's finished flag.

Ammo reads the UI HUD's `unit_data` extension components `inventory`, `weapon_action`, and the wielded slot. The weapon identity uses slot and template plus the item returned by `visual_loadout:item_from_slot()` when available. `WeaponTemplate.current_weapon_template`, `is_ranged` and the vanilla HUD ammo configuration identify supported weapons. `Ammo.current_ammo_in_clips`, `max_ammo_in_clips`, `current_ammo_in_reserve`, and `max_ammo_in_reserve` supply the counts.

Live client timing still needs a playtest. A very short interruption or ammo crossing reversed between samples may be missed. LOW MAG infers firing from a net magazine decrease outside reload and wield actions and with no reserve increase. Unconventional actions that move rounds or change counts need representative weapon tests. A full mod reload during an existing stall can report that stall as newly observed.

- [Player toughness extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/toughness/player_unit_toughness_extension.lua) · [HUD player extensions](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/ui/ui_hud.lua) · [DMF group and checkbox widgets](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/widgets)
- [Decoder client RPCs](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/decoder_device/decoder_device_system.lua) · [Decoder extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/decoder_device/decoder_device_extension.lua)
- [Ammo utility](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/utilities/ammo.lua) · [Vanilla weapon HUD](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/hud/elements/player_weapon/hud_element_player_weapon.lua)
- [DMF mod layout](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/Creating-Mods) · [Hooks](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/hooks) · [Custom HUD elements](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/hud-elements)
- [Vanilla crosshair resolver and draw path](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/hud/elements/crosshair/hud_element_crosshair.lua) · [Centre dot and hit indicators](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/utilities/crosshair.lua)
- [Vanilla HUD lifecycle](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/ui/ui_hud.lua) · [HUD element base](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/hud/elements/hud_element_base.lua)
