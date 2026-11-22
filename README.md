# Darktide Crosshair Alerts

Version **1.0.0-rc1** (release candidate) for the Darktide Mod Framework (DMF).

Crosshair Alerts replaces ordinary reticles with a configurable dot and shows short, high-contrast alerts just below the centre of the screen: a stalled data interrogator, a low magazine or low total ammunition, low or broken toughness, a combat ability or blitz becoming ready, the Arbites dog command, and an expiring stimm. Every alert has its own toggle in Mod Options. Alerts can show an icon with text, an icon only, or text only.

## Requirements

- Darktide with a working **Darktide Mod Loader** and **DMF**.
- **Optional:** [Simple Assets](https://www.nexusmods.com/warhammer40kdarktide/mods/1008) 2.0.x, for the alert icons. Without it every alert is shown as text and everything else works the same.

## Crosshair

- Every reticle vanilla resolves becomes the custom dot, in hip fire, while braced and in alternate-fire spread modes (`assault`, `bfg`, `cross`, `flamer`, `shotgun`, `shotgun_wide`, `spray_n_pray`, `dot_special`, and any type added by a future patch). Hit markers are drawn as before.
- Five types are kept because they carry information the dot can't show, or mean "no reticle": `ironsight` (aiming down sights), `charge_up` (staff charge bars, with the centre restyled as your dot), `charge_up_ads` (Helbore charge bars while aiming), `projectile_drop` (the drop ladder on the gauntlet and Rumbler) and `none` (reloads and similar). The vanilla dot is hidden only while the weapon's alternate fire is a true sight.
- The dot defaults to cyan, 6 UI units (vanilla uses 4), at full opacity. Turning **Replace ordinary crosshairs** off restores every vanilla reticle.

## Alerts

One alert is shown at a time, in a single widget 60 UI units below screen centre. An alert appears at 125% size, settles over 180 ms and fades out over its final 180 ms, with a dark four-direction outline. Alerts run in standard co-op missions and the Psykhanium shooting range, only while you control a living player unit.

| Alert | When it appears | Default |
|---|---|---|
| **TASK** | A data interrogator is interrupted and waiting for a restart. Once per stall; a later stall alerts again. | On, 5 s |
| **RELOAD** | The wielded ranged weapon's magazine drops to its low threshold (20%), or to the small-magazine count (1 round) for magazines of three or more. Never for one- or two-round weapons. | On, 2.5 s |
| **AMMO LOW** | The weapon's total ammunition (magazine plus reserve) falls below its threshold (25%) on a shot. Never for weapons without reserve. | On, 2.5 s |
| **TOUGHNESS** | Toughness drops below 25%. Rearms after recovering above 50%. | On, 2.5 s |
| **BROKEN** | Toughness goes from a positive value to zero. | Off, 2.5 s |
| **ABILITY READY** | The combat ability goes from no usable charge to one. | On, 2 s |
| **GRENADE +N** / **BLITZ +N** | Blitz charges increase. Large pools (more than four) alert only when refilled from empty. | On, 2 s |
| **DOG READY** | The Arbites whistle (Remote Detonation) regains a charge from empty. | On, 2 s |
| **STIM 3s** | An active stimm has your threshold (3 s) or less left. Once per injection, at most 2 s on screen. | On |

**Priority:** TASK, BROKEN, TOUGHNESS, STIM, RELOAD, AMMO LOW, ABILITY READY, DOG READY, then GRENADE or BLITZ. TASK and toughness interrupt ammunition alerts at once; STIM interrupts ammunition and ability alerts. An ammunition alert stays visible for at least one second before another ammunition alert replaces it.

**Colours:** with **Colour alerts by category** on (default), RELOAD is amber, AMMO LOW and BROKEN red, TOUGHNESS cyan, ABILITY READY golden yellow, DOG READY lavender, STIM lime and GRENADE or BLITZ light grey. TASK and previews use **Notification colour** (default #FFF56B). With category colours off, every alert uses Notification colour. The colour tints the icon as well as the text.

### How alerts behave

- **Baselines.** Starting a mission, respawning, hot-joining, equipping a different weapon, changing an ability or changing a threshold records a silent baseline, so a value that is already low does not alert. Being netted, pounced or downed keeps the baseline, so a crossing during a disable shows on release.
- **Ammunition.** Only the wielded ranged weapon counts, and only the clips in use. Reloading, or picking up enough ammunition to get back above the threshold, rearms the alert. Ammunition alerts wait while the ranged weapon is stowed: a crossing can wait up to 10 seconds of weapon-out time and appears when you draw the weapon again if it is still low. A reload keeps the last stable total, so a shot that crosses 25% as a reload starts warns once when the reload ends. A pending RELOAD waits while you reload and is cancelled if the reload refills the magazine.
- **Abilities and blitz.** ABILITY READY follows the synced charge count, as the vanilla ability icon does; a paused cooldown or free-use buff doesn't count. Multi-charge abilities alert only on the empty-to-usable step. Gains in the same 100 ms sample combine, and a further gain while GRENADE +N is visible or waiting updates it (GRENADE +2). Smite and Chain Lightning have no charge count and never alert.
- **Pickups are silent.** Your own grenade and ammunition-crate pickups don't show GRENADE +N: a read-only hook on the pickup interaction gives each pickup a two-second credit, and the next blitz gain within that time uses it. Ordinary ammunition clips count as blitz pickups only with talents that let ammunition refill the blitz (Zealot Throwing Knives). Another player's pickup doesn't affect yours.
- **Waiting notices.** Ability and blitz notices rank below TASK, toughness and ammunition and never interrupt another alert. Each can wait up to four seconds, at most one per alert. A waiting notice is dropped if it expires, its charge is spent or the ability is used again, its toggle is turned off, or the ability changes.
- **Stimm.** STIM reads the running stimm buff, including Stimm Lab's extra duration and later extensions. Covered: the Hive Scum stimm and picked-up combat stimms (power, speed and ability). A stimm already inside the threshold when first seen (joining, respawning) stays silent. A STIM held back by TASK or toughness shows the real remaining time, and is dropped if the effect has ended.
- **Toughness.** The recovery threshold is always at least one percentage point above the warning threshold. If one sample crosses both, only BROKEN is shown (when enabled).

## Display modes and icons

**Alert display mode** under Appearance:

- **Icon + text** (default): the icon sits left of the text and the pair stays centred.
- **Icon only**: the icon alone, centred.
- **Text only**: text alone, as in earlier versions.

Timing, priorities, durations, colours, fade and pop are the same in every mode. Previews (TEST ALERT, TEST WARNING) have no category and stay text in every mode.

The icons are the approved HUD icon pack, shipped as transparent PNGs in `assets/icons/64` and `assets/icons/128`: TASK objective, RELOAD magazine, AMMO LOW low ammunition, TOUGHNESS shield, BROKEN broken shield, ABILITY READY lightning bolt, GRENADE and BLITZ grenade, DOG READY dog command, STIM stimulant. The icon is 28 UI units at the default text size and scales with the text. The 128 px export is used when the icon is drawn larger than 64 screen pixels (for example at 4K).

**Simple Assets is optional.** Icons need it to load the PNGs; it serves them to vanilla's texture loader. Without Simple Assets, while icons are still loading, or for any icon that failed to load, that alert shows its text exactly as in Text only. A missing 64 px or 128 px file falls back to the other size. A failed file is retried at most three times (5 and then 30 seconds apart). Loaded icons are kept across missions and released when the mod unloads.

## Mod Options

Existing saved settings carry over unchanged from every 0.x development build.

| Group | Settings (default) |
|---|---|
| **Crosshair** | Replace ordinary crosshairs (on) · Dot colour (cyan) · Dot size (6, 2–16) · Dot opacity % (100) |
| **Appearance** | Notification colour (#FFF56B) · Notification text size (23, 14–48) · Distance below centre (60, 30–250) · Colour alerts by category (on) · Alert display mode (Icon + text) |
| **Mission Alerts** | TASK (on) · Task text size (26) · Task duration (5 s) |
| **Ammunition** | LOW MAG (on) · Low magazine threshold % (20) · Small magazine warning, rounds (1; 0 turns it off) · Low magazine duration (2.5 s) · LOW AMMO (on) · Low ammunition threshold % (25) · Low ammunition duration (2.5 s) |
| **Toughness** | Warn at low toughness (on) · Warning threshold % (25) · Rearm above % (50) · Warn when toughness breaks (off) |
| **Abilities & Blitz** | Combat ability ready (on) · Blitz or grenade replenished (on) · Arbites dog command ready (on) · Ability and blitz duration (2 s) |
| **Stimm** | Stimm expiration warning (on) · Warning threshold, seconds (3, 1–10) |
| **Testing & Diagnostics** | Enable preview notifications (on) · Preview brief notification (key, unbound) · Brief preview duration (2 s) · on-demand magazine, ammunition supply, toughness and ability diagnostics (off) |

## Install

Close Darktide first. These examples are for Fedora with Steam; set `game_dir` to your own Darktide folder. On other systems, extract the ZIP into the game's `mods` folder and add the line `DarktideCrosshairAlerts` to `mods/mod_load_order.txt`.

**Optional icons:** install Simple Assets 2.0.x from Nexus Mods (mod 1008). Put its `SimpleAssets` folder in the game's `mods` folder, keeping its `bin/simple-assets-runtime.dll`, and add the line `SimpleAssets` to `mods/mod_load_order.txt`. Its position in the list doesn't matter.

### Fresh install

Place `DarktideCrosshairAlerts-1.0.0-rc1.zip` in `~/Downloads` and run:

```bash
(
  set -e
  game_dir="/run/media/$USER/Games/SteamLibrary/steamapps/common/Warhammer 40,000 DARKTIDE"
  archive="$HOME/Downloads/DarktideCrosshairAlerts-1.0.0-rc1.zip"
  mod_dir="$game_dir/mods/DarktideCrosshairAlerts"
  load_order="$game_dir/mods/mod_load_order.txt"

  unzip -tq "$archive"
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

### Upgrade from a 0.x development build

Saved settings, the load order, Simple Assets and DMF stay in place, and no files need deleting. The script backs up the installed mod folder outside the game before replacing its files. (From 0.8.x or earlier, also delete `scripts/mods/DarktideCrosshairAlerts/alert_symbols.lua` from the mod folder after the backup.) Restart the game after upgrading rather than using a DMF reload, so icon textures held by the old build are released.

```bash
(
  set -e
  game_dir="/run/media/$USER/Games/SteamLibrary/steamapps/common/Warhammer 40,000 DARKTIDE"
  archive="$HOME/Downloads/DarktideCrosshairAlerts-1.0.0-rc1.zip"
  mod_dir="$game_dir/mods/DarktideCrosshairAlerts"

  unzip -tq "$archive"
  test -f "$mod_dir/DarktideCrosshairAlerts.mod"
  grep -Fxq 'DarktideCrosshairAlerts' "$game_dir/mods/mod_load_order.txt"
  backup=$(mktemp -d "$HOME/DarktideCrosshairAlerts-previous.XXXXXX")
  cp -a -- "$mod_dir" "$backup/"
  unzip -o "$archive" -d "$game_dir/mods"
  printf 'Previous build saved at %s\n' "$backup/DarktideCrosshairAlerts"
)
```

**Roll back:** close the game and copy the saved folder back over `mods/DarktideCrosshairAlerts`, or extract an earlier ZIP the same way.

**Uninstall:** close the game and remove the line `DarktideCrosshairAlerts` from `mods/mod_load_order.txt`; delete the `mods/DarktideCrosshairAlerts` folder if you no longer need it. Saved settings stay in DMF's settings file.

## Previews and diagnostics

- **Previews:** bind **Preview brief notification** to a key, or type `/dca_preview` in chat for a brief TEST ALERT, `/dca_preview hold` for a persistent TEST WARNING and `/dca_preview clear` to dismiss it. Previews need a living player unit.
- **Diagnostics:** enable the matching option under Testing & Diagnostics, then use `/dca_mag`, `/dca_reserve`, `/dca_toughness` or `/dca_ability` in a mission. Each prints one snapshot (current values, thresholds, armed state, the latest decision) and up to five recent changes. Copy both lines right after a missing or unexpected alert when reporting a problem, and turn diagnostics off when done.

## Known limitations

- **Sampling.** Alerts sample game state every 100 ms. A very short decoder interruption, or a crossing that reverses between samples (including a toughness break and recovery), can be missed.
- **Inferred firing.** RELOAD treats a magazine decrease outside reload and wield actions as a shot. Unusual weapon actions that move rounds may need representative testing.
- **Blitz pickups.** Pickups are matched to blitz gains by time (two-second credits), because the refill happens on the server. A talent regeneration that lands within a pickup's two seconds is silent, and in rare timing the regeneration may use the credit so the refill shows instead.
- **Not covered.** Stimm Supply fields and the corruption-healing stimm have no shared stimm timer and never show STIM. Ordinary dog targeting has no client-visible cooldown, so only the whistle charge shows DOG READY.
- **Mod reload.** A full DMF reload during an existing decoder stall can report that stall as new. Upgrading from 0.9.4 or earlier without restarting the game keeps that build's icon references until the game exits.
- **Icons.** If a vanilla texture request raises an error after it has been counted, that one icon file keeps one loader reference until the game exits; other icons are unaffected.

## Development and testing

Run `luajit tests/test_mod.lua` (or `lua5.1 tests/test_mod.lua`) from the repository root. The offline suite drives the mod entry point, hooks, HUD drawing, alert timelines and priorities, all three display modes, and the icon texture lifecycle against game, DMF and Simple Assets stand-ins modelled on the vanilla sources. Release candidates are also checked in game on Fedora.

The `DarktideCrosshairAlerts` folder is the mod as shipped; release ZIPs contain only that folder.

## Version history

- **1.0.0-rc1:** release candidate built from the verified 0.9.6 source. Version and documentation only.
- **0.9.5–0.9.6:** icon textures retried a bounded number of times after a failure, released on mod unload, and requested one file at a time so one failing file can't affect the others.
- **0.9.2–0.9.4:** audit and review corrections: AMMO LOW across reloads, held RELOAD during reloads, validated and queued ability and blitz notices, STIM extensions, and pickup credits that expire independently.
- **0.9.0–0.9.1:** approved icon artwork through Simple Assets, three display modes, the lightning-bolt ABILITY READY icon and golden-yellow colour.
- **0.7.0–0.8.x:** STIM expiration warning; display-mode option.
- **0.4.0–0.6.x:** abilities, blitz and dog alerts; category colours; total-ammunition LOW AMMO; dot-first crosshair replacement. 0.6.0 removed the peril and heat alerts (their saved values are ignored).
- **0.1.0–0.3.x:** crosshair dot, TASK, LOW MAG, LOW AMMO, TOUGHNESS and BROKEN.

## References

- [Player toughness extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/toughness/player_unit_toughness_extension.lua) · [HUD player extensions](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/ui/ui_hud.lua)
- [Decoder device system](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/decoder_device/decoder_device_system.lua) · [Decoder extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/decoder_device/decoder_device_extension.lua)
- [Ammo utility](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/utilities/ammo.lua) · [Vanilla weapon HUD](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/hud/elements/player_weapon/hud_element_player_weapon.lua)
- [Vanilla crosshair](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/hud/elements/crosshair/hud_element_crosshair.lua) · [Centre dot and hit indicators](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/ui/utilities/crosshair.lua)
- [URL texture loader](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/url_loader/url_loader_manager.lua) · [Simple Assets source](https://github.com/deluxghost/darktide-mods/tree/main/SimpleAssets)
- [DMF mod layout](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/Creating-Mods) · [Hooks](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/hooks) · [Custom HUD elements](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/hud-elements)
