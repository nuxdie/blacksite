class_name Squad
extends RefCounted
## Shared knowledge for a group of guards: where the player was last seen, who is flanking,
## who is searching, and when it's worth throwing a grenade.

var id := ""
var members: Array[Soldier] = []
var last_known := Vector3.ZERO
var last_known_time := -99.0
var known := false
var flanker: Soldier = null
var flank_cooldown := 0.0
var grenade_cooldown := 8.0
var searcher: Soldier = null
var camp_pos := Vector3.ZERO
var camp_time := 0.0


func _init(p_id: String) -> void:
	id = p_id


func since_seen(now: float) -> float:
	return now - last_known_time


func report(pos: Vector3, now: float) -> void:
	last_known = pos
	last_known_time = now
	known = true


func alive_members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for m in members:
		if m.alive:
			out.append(m)
	return out
