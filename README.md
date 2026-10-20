# Last Circle - a battle-royale shooter in Godot 4

Third-person battle royale built **entirely in code** (no external assets - models are
primitive shapes, all sounds are synthesised at start-up, so nothing needs crediting).

## Run
1. Install **Godot 4.3+** (standard build, not .NET).
2. Open `project.godot` in the editor and let it import, then press **F5**.
   (Opening in the editor once is needed so Godot registers the `class_name` scripts.)
3. Wait a few seconds on "Generating map..." while the navmesh bakes.

## Controls
| Key | Action |
|---|---|
| W A S D | move |
| Shift | sprint |
| C / Ctrl (hold) | crouch |
| Z | toggle prone |
| Space | jump |
| LMB / RMB | shoot / aim down sights |
| R | reload |
| 1 / 2 / mouse wheel | primary / secondary weapon |
| F | pick up loot (look for the coloured beams) |
| G | throw grenade |
| H | quick-heal (bandage / medkit) |
| I or Tab | inventory (use / drop / equip with buttons) |
| Esc | release mouse (click to recapture) |

## Feature map (task sections)
1. **Player** - walk/sprint/crouch/prone/jump, health, armor, fall damage, healing items, death. (`player.gd`)
2. **Weapons** - pistol, assault rifle, SMG, shotgun; primary/secondary slots, pickup, switching, reload, magazine +
   reserve ammo, raycast shooting with spread/bloom/recoil, distance falloff, headshots, grenades. (`weapons.gd`, `player.gd`)
3. **Inventory & loot** - weight-based backpack capacity, rarity tiers (damage multiplier), armor, ammo, healing, drop/use UI. (`loot.gd`, `hud.gd`)
4. **Map** - noise-generated 3D terrain, roads (painted), ~320 trees, rocks, 9 enterable houses, rotating minimap. (`main.gd`)
5. **Match system (optional)** - random spawns, countdown, match timer, shrinking blue zone with damage,
   elimination feed, last-player-standing win detection, end screen, restart.
6. **HUD** - health + armor bars, kills, alive count, match timer, crosshair with dynamic spread and hit markers, ammo, minimap. (`hud.gd`)
7. **AI bots** - 11 bots: wander on the navmesh, line-of-sight detection, chase, strafe, shoot, reload, flee the zone,
   fight each other and drop loot when killed. (`bot.gd`)
8. **Animation & SFX** - procedural walk cycle, aim pose, recoil, reload pose, crouch/prone, death fall, muzzle flash + light,
   tracers, synthesised gunshots / reload / footsteps / hit / heal / explosion sounds. (`humanoid.gd`, `sfx.gd`)

**Not included:** section 9 (server-authoritative multiplayer).

## Tuning
Constants at the top of `scripts/main.gd` (`BOT_COUNT`, zone timings, map size) and
`scripts/weapons.gd` (all weapon stats).
