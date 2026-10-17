class_name WeaponData
extends Resource
## One firearm's handling and ballistics. Instances live in res://resources/weapons/.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var mag_size := 30
@export var spare_mags := 4
@export var rpm := 600.0
@export var damage := 30.0
@export var head_mult := 3.5
@export var hip_spread := 0.03
@export var ads_spread := 0.0015
@export var kick := 0.013
@export var kick_yaw := 0.005
@export var reload_time := 2.3
@export var reload_empty_time := 2.75
## How much material a round can punch through (cost units, see Mats.PEN).
@export var penetration := 0.5
## Damage starts falling off past this distance.
@export var effective_range := 60.0
## Radius in metres within which guards hear a shot as gunfire.
@export var loudness := 45.0
@export var suppressed := false
@export var modes: PackedStringArray = ["AUTO", "SEMI"]
@export var ads_fov := 48.0
@export var scoped := false
@export var tracer_chance := 0.35
@export var sound := "rifle"
## Ammunition family. Weapons that share one share loose rounds.
@export var caliber := "5.56"
## Projectiles per shot (shotguns).
@export var pellets := 1
