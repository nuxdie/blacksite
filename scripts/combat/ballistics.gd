class_name Ballistics
## Hitscan bullets that punch through thin materials, losing power on the way.
## Level boxes carry "pen" (resistance per metre) and "half" (extents) metadata,
## so the exit point is computed exactly instead of with a second ray.

## The same rules for everyone: one round's damage to a hit zone, after helmet or body armour,
## range falloff and whatever it already punched through.
static func zone_damage(w: WeaponData, zone: String, helmet: float, armor: float, dist: float, through: float) -> float:
	var mul := 1.0
	match zone:
		"head": mul = w.head_mult * helmet
		"legs": mul = 0.7
		_: mul = armor
	var falloff := clampf(1.0 - (dist - w.effective_range) / (w.effective_range * 1.5), 0.5, 1.0)
	if w.pellets > 1:
		falloff = clampf(1.4 - dist / 14.0, 0.25, 1.0)
	return w.damage * mul * falloff * through


## hit_fn(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary  (needs "t"), {} for none
## wall_fn(point: Vector3, normal: Vector3, exit: bool, material: String) -> void
static func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, power: float, max_dist: float, hit_fn: Callable, wall_fn: Callable) -> Dictionary:
	var org := origin
	var left := max_dist
	var mul := 1.0
	var remaining := power
	var pens := 0
	var exclude: Array[RID] = []
	for _i in 4:
		var q := PhysicsRayQueryParameters3D.create(org, org + dir * left, Layers.WORLD | Layers.GLASS, exclude)
		var hit := space.intersect_ray(q)
		var wall_t := left if hit.is_empty() else org.distance_to(hit.position)
		var tgt: Dictionary = hit_fn.call(org, dir, wall_t)
		if not tgt.is_empty():
			return {"target": tgt, "mul": mul, "pens": pens, "end": org + dir * float(tgt.t)}
		if hit.is_empty():
			return {"mul": mul, "pens": pens, "end": org + dir * left}
		var body: Object = hit.collider
		var mat: String = body.get_meta("mat", "concrete") if body else "concrete"
		wall_fn.call(hit.position, hit.normal, false, mat)
		if body and body.has_method("on_shot"):
			body.call("on_shot")
		var res: float = body.get_meta("pen", 0.0) if body else 0.0
		if res <= 0.0 or not body.has_meta("half"):
			return {"mul": mul, "pens": pens, "end": hit.position, "wall": true}
		var exit_t := _box_exit(body as Node3D, org, dir)
		var cost := (exit_t - wall_t) * res
		if cost >= remaining:
			return {"mul": mul, "pens": pens, "end": hit.position, "wall": true}
		remaining -= cost
		mul *= clampf(1.0 - cost / power * 0.6, 0.35, 1.0)
		pens += 1
		var exit_p := org + dir * exit_t
		wall_fn.call(exit_p, -dir, true, mat)
		exclude.append((body as CollisionObject3D).get_rid())
		org = exit_p + dir * 0.01
		left -= exit_t + 0.01
		if left <= 0.0:
			break
	return {"mul": mul, "pens": pens, "end": org}


## Distance along the ray at which it leaves a box body.
static func _box_exit(body: Node3D, org: Vector3, dir: Vector3) -> float:
	var inv := body.global_transform.affine_inverse()
	var o := inv * org
	var d := inv.basis * dir
	var half: Vector3 = body.get_meta("half")
	var t_exit := INF
	for a in 3:
		if absf(d[a]) < 1e-9:
			continue
		var t1 := (-half[a] - o[a]) / d[a]
		var t2 := (half[a] - o[a]) / d[a]
		t_exit = minf(t_exit, maxf(t1, t2))
	return t_exit


static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t := -b - sq
	if t < 0.0:
		t = -b + sq
	return t


static func spread(d: Vector3, cone: float) -> Vector3:
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var r := d.cross(up).normalized()
	var u := r.cross(d).normalized()
	var ang := randf() * TAU
	var rad := sqrt(randf()) * cone
	return (d + r * cos(ang) * rad + u * sin(ang) * rad).normalized()
