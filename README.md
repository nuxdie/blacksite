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
scripts/player/          Player (movement, stance, lean, vault, wounds), Weapons (mags, chamber, fire, throw),
                         GunModels (procedural guns built around their sight lines), ViewModel (animation)
scripts/ai/              Soldier (perception + behaviour), SoldierModel, SoldierProfile resource, Squad, Cover
scripts/game/            Game (mission flow and shared rules), Command (HQ: alert level, radio checks, alarm), TestRunner
scripts/ui/              Hud, Hints (contextual teaching), Menu, Style
shaders/                 procedural world surfaces, night sky, screen stress effects
resources/weapons/       carbine, smg, dmr, pistol (.tres — tune here)
resources/soldiers/      rifleman, heavy, breacher (.tres — tune here)
assets/fonts/            Rajdhani (SIL OFL, see OFL.txt)
```

## Systems at a glance

- **Insertion**: you start outside the west wall and go in through a breach; extraction is back out the same hole.
- **Zones and routes**: every area has a job, and most have more than one way in.
  - *Loading yard*: insertion, vehicles for cover, a watchtower with a guard and a sweeping searchlight, a ladder onto a container for a perch, and a crate to get over the wall into the main yard.
  - *Gatehouse*: the security booth, its badge holder and the camera terminal.
  - *Main yard*: the open crossing, patrolled and lit.
  - *Office*: the server room (office access, maglock, or crawl in through a vent duct from the west alley), the armoury (security access, or drop in through the roof hatch), and the comms relay on the roof, reached by stairs.
  - *Warehouse*: the objective. The loading doors are open but lit; the south and north doors take a warehouse badge; a fire escape climbs the east alley to the mezzanine; catwalks cross the bay, with a ladder up from the floor. The data office needs secure access, or a climb through its window.
  - *Outside the wire*: a dark perimeter path to a crawl-through culvert under the north wall.
- **Doors**: RFID readers with access levels taken from guards' badges. Cutting a zone's power opens maglock doors and kills strike-locked readers. Guards badge through, so you can follow one.
- **Vertical travel**: stairs and catwalks for everyone; ladders climbed with the interact key, and by guards along navigation links; ducts are crouch-only and loud on sheet metal.
- **Fair detection**: light only counts if it reaches you (walls block lamps, flashlights and the searchlight); closed doors and grilles block sight; footsteps carry half as far through walls. The status line always says why you are being noticed: lit, too close, in view, too loud, or on camera.
- **Sights**: no crosshair. Each gun is modelled so its sight line is exact: red dot (MK4), holographic ring (K7), 3-dot tritium night sights (P9), AK notch and post, LMG peep, shotgun bead, and a 4x scope whose eye-box shadow drifts when you move or breathe.
- **Weapon handling**: closed-bolt guns keep one in the chamber on a tactical reload (30+1); empty reloads need the bolt worked. The pistol slide locks back empty. The shotgun is pumped after every shot and loads shell by shell; firing stops the reload.
- **Wounds**: nothing regenerates. Hits bleed until you bandage (T); a leg hit stops you running until a medkit splints it.
- **Consequences**: HQ runs the radio net. Guards check in every ~95 s, and a dead guard (hidden or not) doesn't answer, so HQ sends people to their post and the site goes to *caution* for the rest of the night (sharper eyes, flashlights, longer searches, scanning posts). A spotted intruder that gets radioed in raises the *alarm*: siren, the nearest guards sent, and a reaction force 70 s later. Kill the spotter before the call goes out (about 3 s), or take the relay down, and HQ never hears it. Without radios, guards still shout to anyone in earshot. Guards walk back to their posts after a search and limp after leg hits.
- **Marking**: a marked guard is tracked only while you can see them; otherwise you keep where you last saw them.

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
