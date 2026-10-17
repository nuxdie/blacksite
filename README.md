# Blacksite

A tactical stealth shooter in Godot 4.7. One operator, one night: recover a drive from a guarded compound and get out.

## Run

```sh
GODOT=~/Applications/Godot/Godot_v4.7.2-stable_linux.x86_64
$GODOT --path .        # play
$GODOT -e --path .     # open in the editor
```

The first launch synthesizes every sound and caches it under `user://` (a few seconds). The navigation mesh is baked at load.

There is no controls screen to memorize. Keys appear on screen when they become useful, and one-time tips teach the rest as situations come up. A reference sheet lives in the pause menu (Esc), along with sensitivity and a button to replay the tips.

## Layout

```
project.godot            input actions are registered at runtime by Settings
scenes/                  main, player, soldier
scripts/core/            Settings (autoload), Sfx (autoload) + Synth, physics layers
scripts/world/           Facility (level, lighting, navmesh), Lamp, Pickup, Mats (materials + penetration table)
scripts/combat/          WeaponData resource, Ballistics (penetrating hitscan), Gadget (thrown equipment)
scripts/player/          Player (movement, stance, lean, vault, damage), Weapons (mags, fire, throw), ViewModel
scripts/ai/              Soldier (perception + behaviour), SoldierModel, SoldierProfile resource, Squad, Cover
scripts/game/            Game (mission flow and shared rules), TestRunner
scripts/ui/              Hud, Hints (contextual teaching), Menu, Style
shaders/                 procedural world surfaces, night sky, screen stress effects
resources/weapons/       carbine, smg, dmr, pistol (.tres — tune here)
resources/soldiers/      rifleman, heavy, breacher (.tres — tune here)
assets/fonts/            Rajdhani (SIL OFL, see OFL.txt)
```

## Systems at a glance

- **Stealth**: guards build awareness from distance, light (lamps, moonlight, their own flashlights), your stance, movement and exposure. Lamps can be shot out. Bodies are found by sight, and bodies in the dark only up close.
- **Squads**: shared last-known position; cover selection with peeking, suppressive fire, a designated flanker, grenades against campers, sound-based tracking, staged searches.
- **Ballistics**: rounds lose power through plaster, wood, sheet metal and containers, and stop at concrete and steel. This applies both ways.
- **Arsenal**: three starting primaries, a suppressed sidearm, magazines tracked individually, and four thrown gadgets with an arc preview. Smoke is a volumetric fog volume that blocks AI sight.
- **Scavenging**: every weapon has a caliber (5.56, 7.62, 9mm, 12ga). Guards drop their own weapon (AR-7, LMG-80, BRX-12) with what's left in its magazine, plus the loose rounds they carried. Rounds only load into weapons of the same caliber, so a marksman rifle can live off riflemen and a carbine can't. Swapping your primary leaves the old one on the ground.
- **Hacking** (hold H on remote devices, hold F on physical ones; progress persists):
  - *Cameras* sweep, build awareness like guards, and radio in your position (and any bodies they see). Hacking one loops its feed for 90 s.
  - *Comms relay* (office roof) jams all guard radio for two minutes: squad alerts and camera alarms go nowhere.
  - *Security terminal* (guard booth) takes every camera offline for good.
  - *Lamps* can be switched off silently instead of shot out.
  - *The drive* is now a download at the warehouse laptop. Hold it for nine seconds; if you're interrupted, the progress is kept.

## Automated checks

```sh
$GODOT --headless --path . -- --autotest   # gameplay assertions, prints JSON
$GODOT --headless --path . -- --sim=60     # combat bot vs the AI for 60 s
$GODOT --path . -- --shots=/tmp/shots      # rendered screenshots at fixed viewpoints
```

Test runs never write to your saved settings.
