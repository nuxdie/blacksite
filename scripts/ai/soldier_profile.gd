class_name SoldierProfile
extends Resource
## Stats and temperament for one kind of guard. Instances live in res://resources/soldiers/.

@export var id := ""
@export var display_name := ""
@export var health := 100.0
@export var run_speed := 4.6
@export var walk_speed := 1.7
@export var mag_size := 30
@export var fire_interval := 0.1
@export var burst_min := 3
@export var burst_max := 5
@export var pause_min := 0.35
@export var pause_max := 0.8
@export var damage := 11.0
@export var spread_mult := 1.0
@export var penetration := 0.5
## Damage multiplier on head hits (helmets reduce it below 1).
@export var helmet := 1.0
## Damage multiplier on body hits (plate carriers reduce it below 1).
@export var armor := 1.0
@export var preferred_range := 15.0
@export var grenades := 1
## rifle | lmg | shotgun
@export var weapon_kind := "rifle"
@export var visor_color := Color("ff3a1a")
@export var uniform_color := Color("3c4436")
## The WeaponData id this guard carries, dropped on death.
@export var weapon_id := "ar7"
## Loose rounds of that weapon's caliber carried in pouches.
@export var carried_rounds := 60
## hold | advance | rush
@export var doctrine := "hold"
