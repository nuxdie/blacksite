class_name Cover
## Cover and flanking positions, sampled from the navigation mesh and validated with sight lines.

enum { HOLD, RETREAT, FLANK }


## A point hides a crouched body from the threat's eyes.
static func protects(game: Game, point: Vector3, threat: Vector3) -> bool:
	return not game.los(point + Vector3.UP * 0.95, threat + Vector3.UP * 1.4)


## Returns {point, fire, low} or {} if nothing useful was found.
static func find(s: Soldier, threat: Vector3, kind: int) -> Dictionary:
	var game := s.game
	var map := s.get_world_3d().navigation_map
	var t_eye := threat + Vector3.UP * 1.4
	var t_low := threat + Vector3.UP * 0.9
	var center := threat if kind == FLANK else s.global_position
	var r_min := 7.0 if kind == FLANK else 0.5
	var r_max := 22.0 if kind == FLANK else (20.0 if kind == RETREAT else 13.0)
	var view := game.player.view_dir()
	var best := {}
	var best_score := -INF
	for _k in 40:
		var a := randf() * TAU
		var r := randf_range(r_min, r_max)
		var probe := Vector3(center.x + cos(a) * r, s.global_position.y, center.z + sin(a) * r)
		var p := NavigationServer3D.map_get_closest_point(map, probe)
		if Vector2(p.x - probe.x, p.z - probe.z).length() > 1.5 or absf(p.y - s.global_position.y) > 5.5:
			continue
		var d_threat := Vector2(p.x - threat.x, p.z - threat.z).length()
		if d_threat < 4.0 or _claimed(s, p):
			continue
		var low := p + Vector3.UP * 0.95
		var stand := p + Vector3.UP * 1.55
		var score := 0.0
		var fire := p
		var is_low := false
		if kind == FLANK:
			if not game.los(stand, t_low):
				continue
			score += 8.0
			var to_p := (p - game.player.global_position).normalized()
			if to_p.x * view.x + to_p.z * view.z < 0.3:
				score += 4.0
			for o in s.squad.members:
				if o != s and o.alive:
					var b1 := atan2(o.global_position.x - threat.x, o.global_position.z - threat.z)
					var b2 := atan2(p.x - threat.x, p.z - threat.z)
					score += absf(angle_difference(b1, b2)) * 1.5
			score -= absf(d_threat - 11.0) * 0.3
		else:
			if game.los(low, t_eye):
				continue
			if game.los(stand, t_eye):
				is_low = true
				score += 6.0
			else:
				var pk := _peek_point(game, map, p, threat)
				if pk != Vector3.INF:
					fire = pk
					score += 5.0
				elif kind != RETREAT:
					score -= 3.0
			# real cover beats concealment
			var hit := game.ray(low, low + (t_eye - low).normalized() * 2.2)
			if not hit.is_empty():
				var body: Object = hit.collider
				score += 1.0 if float(body.get_meta("pen", 0.0)) > 0.0 else 3.0
			score -= absf(d_threat - (24.0 if kind == RETREAT else s.profile.preferred_range)) * 0.15
			score += clampf(p.y - threat.y, -1.0, 3.0) * 0.6
		score -= p.distance_to(s.global_position) * (0.12 if kind == FLANK else 0.3)
		score += randf()
		if score > best_score:
			best_score = score
			best = {"point": p, "fire": fire, "low": is_low}
	return best


static func _peek_point(game: Game, map: RID, p: Vector3, threat: Vector3) -> Vector3:
	var to := threat - p
	to.y = 0.0
	var side := Vector3(-to.z, 0.0, to.x).normalized()
	for off: float in [1.0, -1.0, 1.6, -1.6]:
		var q := NavigationServer3D.map_get_closest_point(map, p + side * off)
		if absf(q.y - p.y) > 0.4 or q.distance_to(p + side * off) > 0.5:
			continue
		if game.los(q + Vector3.UP * 1.55, threat + Vector3.UP * 1.4):
			return q
	return Vector3.INF


static func _claimed(s: Soldier, p: Vector3) -> bool:
	for o in s.game.soldiers:
		if o != s and o.alive and o.has_cover and Vector2(o.cover_point.x - p.x, o.cover_point.z - p.z).length() < 2.5 and absf(o.cover_point.y - p.y) < 1.0:
			return true
	return false
