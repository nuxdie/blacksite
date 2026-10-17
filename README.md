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
- **Security, power and comms**: nothing is hacked through the air.
  - *Cameras* (five) sweep, build awareness like guards do, and radio in your position and any bodies they see.
  - *The security network* is reached at three access points: the booth terminal, a junction box on the warehouse's south wall, and the server cabinet in the office. With the booth guard's badge, login is instant and clean. Without it, you spend 15 s bypassing security and it shows up in their logs.
  - *The tablet* shows live night-vision feeds. Looping a feed is quiet and lasts 90 s. Disabling a camera is permanent, but security sends a guard to fix it. With admin access you can shut the whole system down, and someone will come to the terminal to bring it back.
  - *Trace*: every action leaves log entries. Fill the meter and intrusion detection kicks you out, locks that port for a minute, and sends guards to look.
  - *Breakers* cut a zone's lights silently. Guards notice and send someone to reset the panel.
  - *Comms relay* (office roof): sabotage it and their radio dies, so alarms and squad calls go nowhere, until a guard walks up and repairs it.
  - *The data*: plug a drive into the laptop and it copies on its own for 35 s. Any guard who wanders close will pull it. Come back to retrieve it.

## Automated checks

```sh
$GODOT --headless --path . -- --autotest   # gameplay assertions, prints JSON
$GODOT --headless --path . -- --sim=60     # combat bot vs the AI for 60 s
$GODOT --path . -- --shots=/tmp/shots      # rendered screenshots at fixed viewpoints
```

Test runs never write to your saved settings.
