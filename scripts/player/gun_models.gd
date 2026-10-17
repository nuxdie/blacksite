class_name GunModels
extends RefCounted
## First-person weapon models built from boxes and lathed profiles.
##
## Every gun shares one convention: the bore runs along -Z through the origin, z = 0 sits at the
## trigger, and every sight is built so its line of sight is horizontal at height `sight_y`.
## Aiming then only has to put that line through the eye; nothing is tuned by eye per weapon.

const VM_FOV := 54.0
const LAYER := 2

var _mats: Dictionary = {}


func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var spec: Array = {
		"poly": [Color("1d1e20"), 0.7, 0.05],
		"bluing": [Color("26282b"), 0.38, 0.85],
		"steel": [Color("3a3d41"), 0.32, 0.9],
		"alu": [Color("2c2e30"), 0.5, 0.6],
		"wood": [Color("4f2f1a"), 0.55, 0.0],
		"od": [Color("3b4030"), 0.85, 0.0],
		"fde": [Color("6e5f46"), 0.8, 0.0],
		"rubber": [Color("141414"), 0.95, 0.0],
		"brass": [Color("b08a3c"), 0.3, 1.0],
		"hull": [Color("7a1d16"), 0.6, 0.0],
		"lacquer": [Color("4a3b22"), 0.5, 0.4],
		"glove": [Color("1a1a19"), 0.9, 0.0],
		"glove_pad": [Color("2b2a27"), 0.95, 0.0],
		"sleeve": [Color("2f3529"), 0.95, 0.0],
		"cuff": [Color("23281f"), 0.95, 0.0],
		"port": [Color("060606"), 1.0, 0.0],
	}.get(key, [Color.MAGENTA, 0.5, 0.0])
	m.albedo_color = spec[0]
	m.roughness = spec[1]
	m.metallic = spec[2]
	_finish(m)
	_mats[key] = m
	return m


## Self-lit sight elements: red dots, holographic reticles, tritium inserts.
func glow(key: String, color: Color, energy: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy)
	_finish(m)
	_mats[key] = m
	return m


## Coated optical glass: almost clear, with a faint tint and a sharp highlight.
func glass(key: String, tint: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = 0.05
	m.metallic = 0.2
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(m)
	_mats[key] = m
	return m


func _finish(m: StandardMaterial3D) -> void:
	m.use_fov_override = true
	m.fov_override = VM_FOV
	m.use_z_clip_scale = true
	m.z_clip_scale = 0.2


# ------------------------------------------------------------------ primitives

func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = LAYER
	parent.add_child(mi)
	return mi


func box(parent: Node3D, size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, m, pos, rot)


func sphere(parent: Node3D, r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return _add(parent, sm, m, pos, Vector3.ZERO)


## Solid cylinder along Z, centred on pos.
func cyl(parent: Node3D, r: float, length: float, m: Material, pos: Vector3, segs := 16) -> MeshInstance3D:
	var h := length * 0.5
	return lathe(parent, [Vector2(-h, 0), Vector2(-h, r), Vector2(h, r), Vector2(h, 0)], m, pos, segs)


## Hollow tube along Z, centred on pos.
func tube(parent: Node3D, r_in: float, r_out: float, length: float, m: Material, pos: Vector3, segs := 24) -> MeshInstance3D:
	var h := length * 0.5
	return lathe(parent, [Vector2(-h, r_in), Vector2(-h, r_out), Vector2(h, r_out), Vector2(h, r_in), Vector2(-h, r_in)], m, pos, segs)


## A surface of revolution around Z. Profile points are (z, radius); walk the outside toward +z
## so the outward side is on the left of travel.
func lathe(parent: Node3D, profile: Array, m: Material, pos: Vector3, segs := 16, rot := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if a.y < 0.00001 and b.y < 0.00001:
			continue
		var d := b - a
		var n2 := Vector2(-d.y, d.x).normalized()
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var c0 := Vector2(cos(t0), sin(t0))
			var c1 := Vector2(cos(t1), sin(t1))
			var p00 := Vector3(c0.x * a.y, c0.y * a.y, a.x)
			var p10 := Vector3(c0.x * b.y, c0.y * b.y, b.x)
			var p11 := Vector3(c1.x * b.y, c1.y * b.y, b.x)
			var p01 := Vector3(c1.x * a.y, c1.y * a.y, a.x)
			var nm := (Vector3(c0.x * n2.y, c0.y * n2.y, n2.x) + Vector3(c1.x * n2.y, c1.y * n2.y, n2.x)).normalized()
			var n0 := Vector3(c0.x * n2.y, c0.y * n2.y, n2.x).normalized()
			var n1 := Vector3(c1.x * n2.y, c1.y * n2.y, n2.x).normalized()
			_tri(st, [p00, p10, p11], [n0, n0, n1], nm)
			_tri(st, [p00, p11, p01], [n0, n1, n1], nm)
	return _add(parent, st.commit(), m, pos, rot)


## Godot treats clockwise triangles as front faces: wind each one against its outward normal.
func _tri(st: SurfaceTool, p: Array, n: Array, outward: Vector3) -> void:
	var c: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if c.length_squared() < 1e-14:
		return
	var order := [0, 1, 2] if c.dot(outward) < 0.0 else [0, 2, 1]
	for k: int in order:
		st.set_normal(n[k])
		st.add_vertex(p[k])


func pivot(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


## A box stretched between two points (limbs).
func limb(parent: Node3D, from: Vector3, to: Vector3, w: float, h: float, m: Material) -> MeshInstance3D:
	var d := to - from
	var mi := box(parent, Vector3(w, h, d.length()), m, (from + to) * 0.5)
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.basis = Basis.looking_at(d, up)
	return mi


# ------------------------------------------------------------------ hands

## Support hand cupping a round handguard of radius r from below; the forearm runs back out of view.
func support_hand(parent: Node3D, pos: Vector3, r: float, elbow := Vector3(-0.17, -0.26, 0.2)) -> Node3D:
	var h := pivot(parent, pos)
	var g := mat("glove")
	box(h, Vector3(r * 2.0 + 0.012, 0.016, 0.082), g, Vector3(0, -r - 0.006, 0))
	box(h, Vector3(0.013, r * 1.6, 0.078), g, Vector3(-r - 0.004, -r * 0.2, 0.002))
	for i in 4:
		box(h, Vector3(0.012, r * 1.3, 0.017), mat("glove_pad"), Vector3(r + 0.003, -r * 0.35, -0.028 + i * 0.019))
	box(h, Vector3(0.011, 0.011, 0.045), g, Vector3(-r - 0.002, r * 0.55, -0.012), Vector3(0, 0.15, 0))
	box(h, Vector3(0.052, 0.04, 0.045), g, Vector3(-0.012, -r - 0.014, 0.05))
	var wrist := Vector3(-0.014, -r - 0.018, 0.07)
	limb(h, wrist, wrist + (elbow - wrist) * 0.22, 0.05, 0.045, mat("cuff"))
	limb(h, wrist + (elbow - wrist) * 0.2, elbow, 0.068, 0.066, mat("sleeve"))
	limb(h, elbow, elbow + Vector3(-0.06, -0.12, 0.25), 0.08, 0.08, mat("sleeve"))
	return h


## Firing hand wrapped around a pistol grip with the given rake.
func grip_hand(parent: Node3D, pos: Vector3, rake: float, elbow := Vector3(0.15, -0.3, 0.3)) -> Node3D:
	var h := pivot(parent, pos, Vector3(rake, 0, 0))
	var g := mat("glove")
	box(h, Vector3(0.044, 0.07, 0.03), g, Vector3(0, -0.004, 0.016))
	for i in 3:
		box(h, Vector3(0.046, 0.017, 0.022), mat("glove_pad"), Vector3(0.002, -0.022 - i * 0.019, -0.022))
	box(h, Vector3(0.012, 0.012, 0.046), g, Vector3(-0.02, 0.03, -0.012), Vector3(-0.15 - rake, 0, 0))
	box(h, Vector3(0.011, 0.011, 0.04), g, Vector3(0.017, 0.022, -0.035), Vector3(-rake, 0, 0))
	var wrist := Vector3(0.004, -0.02, 0.04)
	var e := h.basis.inverse() * elbow
	limb(h, wrist, wrist + (e - wrist) * 0.22, 0.05, 0.05, mat("cuff"))
	limb(h, wrist + (e - wrist) * 0.2, e, 0.07, 0.068, mat("sleeve"))
	limb(h, e, e + Vector3(0.05, -0.1, 0.25), 0.08, 0.08, mat("sleeve"))
	return h


# ------------------------------------------------------------------ sights

## Tube red dot (micro prism-less reflex) on a riser; the dot sits on the sight line at the lens.
func red_dot(parent: Node3D, sight_y: float, z_back: float, rail_y: float) -> void:
	var a := mat("alu")
	var zf := z_back - 0.056
	box(parent, Vector3(0.024, sight_y - rail_y - 0.012, 0.034), a, Vector3(0, (rail_y + sight_y - 0.012) * 0.5, z_back - 0.026))
	box(parent, Vector3(0.03, 0.006, 0.04), a, Vector3(0, rail_y + 0.003, z_back - 0.026))
	lathe(parent, [
		Vector2(zf, 0.0105), Vector2(zf, 0.0148), Vector2(zf + 0.009, 0.0148), Vector2(zf + 0.011, 0.0136),
		Vector2(z_back - 0.011, 0.0136), Vector2(z_back - 0.009, 0.0146), Vector2(z_back, 0.0146),
		Vector2(z_back, 0.0112), Vector2(zf, 0.0105)], a, Vector3(0, sight_y, 0), 28)
	box(parent, Vector3(0.012, 0.011, 0.014), a, Vector3(0, sight_y + 0.0175, z_back - 0.03))
	box(parent, Vector3(0.011, 0.012, 0.014), a, Vector3(0.0175, sight_y, z_back - 0.03))
	cyl(parent, 0.0106, 0.0008, glass("lens_dot", Color(0.55, 0.62, 0.9, 0.05)), Vector3(0, sight_y, zf + 0.002), 24)
	sphere(parent, 0.00042, glow("dot_red", Color(1.0, 0.08, 0.04), 6.0), Vector3(0, sight_y, zf + 0.004))


## Holographic sight: open rectangular window, ring-and-dot reticle projected on the front glass.
func holo(parent: Node3D, sight_y: float, z_back: float, rail_y: float) -> void:
	var p := mat("poly")
	var a := mat("alu")
	var len := 0.078
	var zc := z_back - len * 0.5
	var win_b := sight_y - 0.0105
	box(parent, Vector3(0.034, win_b - rail_y, 0.095), p, Vector3(0, (rail_y + win_b) * 0.5, zc - 0.006))
	box(parent, Vector3(0.037, 0.0035, len), a, Vector3(0, sight_y + 0.0128, zc))
	for sx: float in [-1.0, 1.0]:
		box(parent, Vector3(0.0035, 0.026, len), a, Vector3(sx * 0.0168, sight_y + 0.0003, zc))
	box(parent, Vector3(0.008, 0.006, 0.018), p, Vector3(0.008, win_b + 0.003, z_back - 0.006))
	box(parent, Vector3(0.008, 0.006, 0.018), p, Vector3(-0.008, win_b + 0.003, z_back - 0.006))
	var g := glass("lens_holo", Color(0.6, 0.85, 0.75, 0.05))
	box(parent, Vector3(0.03, 0.022, 0.0008), g, Vector3(0, sight_y, z_back - len + 0.004))
	box(parent, Vector3(0.03, 0.022, 0.0008), g, Vector3(0, sight_y, z_back - 0.002))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0041
	ring.outer_radius = 0.0045
	ring.rings = 48
	ring.ring_segments = 4
	var rm := glow("holo_red", Color(1.0, 0.12, 0.06), 4.0)
	_add(parent, ring, rm, Vector3(0, sight_y, z_back - len + 0.006), Vector3(PI / 2, 0, 0))
	sphere(parent, 0.00038, rm, Vector3(0, sight_y, z_back - len + 0.006))


## Ring aperture (peep) for iron sights.
func peep(parent: Node3D, sight_y: float, z: float, base_y: float) -> void:
	var s := mat("bluing")
	tube(parent, 0.0034, 0.0056, 0.003, s, Vector3(0, sight_y, z), 28)
	box(parent, Vector3(0.004, sight_y - 0.0054 - base_y, 0.003), s, Vector3(0, (base_y + sight_y - 0.0054) * 0.5, z))
	for sx: float in [-1.0, 1.0]:
		box(parent, Vector3(0.0025, sight_y + 0.006 - base_y, 0.014), s, Vector3(sx * 0.011, (base_y + sight_y + 0.006) * 0.5, z))


## Open rear notch: two blades whose tops are the sight line, a notch `w` wide and `depth` deep.
func notch(parent: Node3D, sight_y: float, z: float, w: float, depth: float, blade_w: float, base_y: float, m: Material) -> void:
	for sx: float in [-1.0, 1.0]:
		box(parent, Vector3(blade_w, sight_y - base_y, 0.004), m, Vector3(sx * (w + blade_w) * 0.5, (sight_y + base_y) * 0.5, z))
	box(parent, Vector3(w, sight_y - depth - base_y, 0.004), m, Vector3(0, (sight_y - depth + base_y) * 0.5, z))


## Front post, optionally with protective ears either side.
func post(parent: Node3D, sight_y: float, z: float, w: float, base_y: float, ears: bool, m: Material) -> void:
	box(parent, Vector3(w, sight_y - base_y, w), m, Vector3(0, (sight_y + base_y) * 0.5, z))
	if ears:
		for sx: float in [-1.0, 1.0]:
			box(parent, Vector3(0.003, sight_y + 0.004 - base_y, 0.012), m, Vector3(sx * 0.009, (sight_y + 0.004 + base_y) * 0.5, z))


# ------------------------------------------------------------------ guns
#
# Each builder returns a rig:
#   root, sight_y, ads (origin offset that puts the sight line through the eye), hip,
#   mag (pivot that drops out on reload), bolt (part that cycles), bolt_travel, cycles (moves on every
#   shot), muzzle, eject, lhand (support hand pivot), lhand_rest, case (casing kind), extra parts.

func build(id: String) -> Dictionary:
	match id:
		"carbine": return _carbine()
		"smg": return _smg()
		"dmr": return _dmr()
		"pistol": return _pistol()
		"ar7": return _ar7()
		"lmg": return _lmg()
		"shotgun": return _shotgun()
	return _carbine()


func _rig(root: Node3D, sight_y: float, eye: float, rear_z: float, hip: Vector3) -> Dictionary:
	return {"root": root, "sight_y": sight_y, "ads": Vector3(0, -sight_y, -eye - rear_z), "hip": hip}


func _stanag(parent: Node3D, m: Material) -> void:
	box(parent, Vector3(0.022, 0.068, 0.061), m, Vector3(0, -0.034, 0))
	box(parent, Vector3(0.022, 0.06, 0.06), m, Vector3(0, -0.092, -0.01), Vector3(0.22, 0, 0))
	box(parent, Vector3(0.026, 0.01, 0.068), mat("poly"), Vector3(0, -0.124, -0.018), Vector3(0.22, 0, 0))


func _carbine() -> Dictionary:
	var r := Node3D.new()
	var p := mat("poly")
	var a := mat("alu")
	var s := mat("bluing")
	box(r, Vector3(0.03, 0.032, 0.2), a, Vector3(0, 0.01, -0.03))
	box(r, Vector3(0.021, 0.008, 0.2), a, Vector3(0, 0.03, -0.03))
	for i in 11:
		box(r, Vector3(0.023, 0.0035, 0.004), s, Vector3(0, 0.0325, 0.06 - i * 0.018))
	box(r, Vector3(0.0015, 0.012, 0.04), mat("port"), Vector3(0.0153, 0.012, -0.02))
	box(r, Vector3(0.0035, 0.008, 0.012), s, Vector3(0.0165, 0.004, 0.025))
	box(r, Vector3(0.027, 0.034, 0.15), a, Vector3(0, -0.022, 0.0))
	box(r, Vector3(0.031, 0.044, 0.072), a, Vector3(0, -0.04, -0.056))
	box(r, Vector3(0.024, 0.004, 0.052), a, Vector3(0, -0.046, 0.008))
	box(r, Vector3(0.026, 0.084, 0.034), p, Vector3(0, -0.07, 0.048), Vector3(-0.36, 0, 0))
	cyl(r, 0.015, 0.16, a, Vector3(0, 0.002, 0.15))
	box(r, Vector3(0.042, 0.06, 0.13), mat("fde"), Vector3(0, -0.014, 0.25))
	box(r, Vector3(0.044, 0.1, 0.02), mat("rubber"), Vector3(0, -0.03, 0.325))
	lathe(r, [Vector2(-0.4, 0.0), Vector2(-0.4, 0.021), Vector2(-0.39, 0.023), Vector2(-0.125, 0.023), Vector2(-0.115, 0.021), Vector2(-0.115, 0.0)], mat("fde"), Vector3(0, 0.004, 0), 8, Vector3(0, 0, PI / 8))
	box(r, Vector3(0.02, 0.007, 0.28), a, Vector3(0, 0.029, -0.26))
	cyl(r, 0.0085, 0.13, s, Vector3(0, 0, -0.46))
	box(r, Vector3(0.02, 0.022, 0.025), s, Vector3(0, 0.002, -0.43))
	lathe(r, [Vector2(-0.57, 0.0), Vector2(-0.57, 0.0105), Vector2(-0.525, 0.0115), Vector2(-0.52, 0.009), Vector2(-0.52, 0.0)], s, Vector3.ZERO, 6)
	box(r, Vector3(0.016, 0.008, 0.028), s, Vector3(0, 0.0365, -0.38))
	red_dot(r, 0.068, -0.005, 0.034)
	var mag := pivot(r, Vector3(0, -0.06, -0.056))
	_stanag(mag, a)
	var bolt := pivot(r, Vector3(0, 0.024, 0.09))
	box(bolt, Vector3(0.036, 0.007, 0.012), a, Vector3.ZERO)
	grip_hand(r, Vector3(0, -0.068, 0.05), -0.36)
	var lh := support_hand(r, Vector3(0, 0.004, -0.29), 0.023)
	var rig := _rig(r, 0.068, 0.2, -0.005, Vector3(0.155, -0.165, -0.33))
	rig.merge({"mag": mag, "bolt": bolt, "bolt_travel": Vector3(0, 0, 0.065), "cycles": false, "muzzle": Vector3(0, 0, -0.58), "eject": Vector3(0.02, 0.012, -0.02), "lhand": lh, "case": "rifle"})
	return rig


func _smg() -> Dictionary:
	var r := Node3D.new()
	var p := mat("poly")
	var s := mat("bluing")
	box(r, Vector3(0.03, 0.034, 0.24), s, Vector3(0, 0.0, -0.04))
	cyl(r, 0.0155, 0.24, s, Vector3(0, 0.009, -0.04))
	box(r, Vector3(0.0015, 0.011, 0.035), mat("port"), Vector3(0.0158, 0.008, -0.01))
	box(r, Vector3(0.022, 0.008, 0.09), s, Vector3(0, 0.03, -0.03))
	box(r, Vector3(0.03, 0.03, 0.09), p, Vector3(0, -0.028, 0.02))
	box(r, Vector3(0.028, 0.086, 0.036), p, Vector3(0, -0.066, 0.042), Vector3(-0.3, 0, 0))
	box(r, Vector3(0.022, 0.004, 0.05), p, Vector3(0, -0.047, 0.0))
	lathe(r, [Vector2(-0.44, 0.0), Vector2(-0.44, 0.018), Vector2(-0.435, 0.0235), Vector2(-0.16, 0.0235), Vector2(-0.16, 0.0)], s, Vector3(0, 0.0, 0), 20)
	cyl(r, 0.0275, 0.13, p, Vector3(0, -0.002, -0.215), 14)
	for i in 5:
		box(r, Vector3(0.057, 0.004, 0.006), mat("rubber"), Vector3(0, -0.012, -0.17 - i * 0.022))
	cyl(r, 0.0055, 0.1, s, Vector3(0, 0.02, -0.2))
	for sx: float in [-1.0, 1.0]:
		cyl(r, 0.0042, 0.2, s, Vector3(sx * 0.014, -0.004, 0.18), 8)
	box(r, Vector3(0.04, 0.085, 0.02), mat("rubber"), Vector3(0, -0.022, 0.285))
	holo(r, 0.068, 0.0, 0.034)
	var mag := pivot(r, Vector3(0, -0.03, -0.052))
	box(mag, Vector3(0.019, 0.08, 0.03), s, Vector3(0, -0.04, 0), Vector3(0.12, 0, 0))
	box(mag, Vector3(0.019, 0.072, 0.03), s, Vector3(0, -0.108, -0.017), Vector3(0.32, 0, 0))
	var bolt := pivot(r, Vector3(-0.02, 0.019, -0.185))
	box(bolt, Vector3(0.022, 0.006, 0.008), s, Vector3(-0.008, 0, 0))
	grip_hand(r, Vector3(0, -0.066, 0.044), -0.3)
	var lh := support_hand(r, Vector3(0, -0.002, -0.215), 0.028)
	var rig := _rig(r, 0.068, 0.2, 0.0, Vector3(0.15, -0.16, -0.31))
	rig.merge({"mag": mag, "bolt": bolt, "bolt_travel": Vector3(0, 0, 0.06), "cycles": false, "muzzle": Vector3(0, 0, -0.44), "eject": Vector3(0.02, 0.008, -0.01), "lhand": lh, "case": "pistol"})
	return rig


func _dmr() -> Dictionary:
	var r := Node3D.new()
	var od := mat("od")
	var s := mat("bluing")
	box(r, Vector3(0.046, 0.05, 0.31), od, Vector3(0, -0.022, -0.225))
	box(r, Vector3(0.036, 0.058, 0.11), od, Vector3(0, -0.04, 0.05), Vector3(-0.22, 0, 0))
	box(r, Vector3(0.042, 0.1, 0.24), od, Vector3(0, -0.055, 0.24), Vector3(0.08, 0, 0))
	box(r, Vector3(0.045, 0.12, 0.02), mat("rubber"), Vector3(0, -0.064, 0.36), Vector3(0.08, 0, 0))
	box(r, Vector3(0.032, 0.03, 0.22), s, Vector3(0, 0.006, -0.02))
	box(r, Vector3(0.03, 0.017, 0.17), od, Vector3(0, 0.014, -0.2))
	cyl(r, 0.0098, 0.32, s, Vector3(0, 0, -0.46))
	cyl(r, 0.0075, 0.1, s, Vector3(0, -0.018, -0.46))
	lathe(r, [Vector2(-0.675, 0.0), Vector2(-0.675, 0.0115), Vector2(-0.62, 0.0125), Vector2(-0.615, 0.01), Vector2(-0.615, 0.0)], s, Vector3.ZERO, 10)
	box(r, Vector3(0.0035, 0.016, 0.004), s, Vector3(0, 0.018, -0.65))
	box(r, Vector3(0.03, 0.01, 0.13), s, Vector3(0, 0.026, -0.045))
	for z: float in [-0.09, 0.0]:
		box(r, Vector3(0.03, 0.03, 0.016), s, Vector3(0, 0.046, z))
	var sy := 0.062
	lathe(r, [
		Vector2(-0.23, 0.0), Vector2(-0.23, 0.0225), Vector2(-0.16, 0.0225), Vector2(-0.125, 0.0128),
		Vector2(0.065, 0.0128), Vector2(0.085, 0.0185), Vector2(0.14, 0.0195), Vector2(0.14, 0.0)], s, Vector3(0, sy, 0), 28)
	cyl(r, 0.0205, 0.002, glass("lens_obj", Color(0.25, 0.3, 0.6, 0.55)), Vector3(0, sy, -0.231), 24)
	cyl(r, 0.017, 0.002, glass("lens_eye", Color(0.05, 0.08, 0.12, 0.85)), Vector3(0, sy, 0.141), 24)
	var turret := pivot(r, Vector3(0, sy, -0.03), Vector3(-PI / 2, 0, 0))
	cyl(turret, 0.0105, 0.02, s, Vector3(0, 0, 0.022), 14)
	var wind := pivot(r, Vector3(0, sy, -0.03), Vector3(0, PI / 2, 0))
	cyl(wind, 0.0105, 0.02, s, Vector3(0, 0, 0.022), 14)
	var mag := pivot(r, Vector3(0, -0.035, -0.07))
	box(mag, Vector3(0.03, 0.075, 0.074), s, Vector3(0, -0.035, 0), Vector3(0.08, 0, 0))
	var bolt := pivot(r, Vector3(0.021, 0.006, -0.07))
	box(bolt, Vector3(0.008, 0.012, 0.05), s, Vector3.ZERO)
	box(bolt, Vector3(0.014, 0.012, 0.012), s, Vector3(0.006, 0, -0.02))
	grip_hand(r, Vector3(0, -0.045, 0.055), -0.22)
	var lh := support_hand(r, Vector3(0, -0.016, -0.24), 0.026)
	var rig := _rig(r, sy, 0.085, 0.14, Vector3(0.16, -0.17, -0.36))
	rig.merge({"mag": mag, "bolt": bolt, "bolt_travel": Vector3(0, 0, 0.075), "cycles": true, "muzzle": Vector3(0, 0, -0.68), "eject": Vector3(0.02, 0.012, -0.04), "lhand": lh, "case": "rifle"})
	return rig


func _pistol() -> Dictionary:
	var r := Node3D.new()
	var p := mat("poly")
	var s := mat("bluing")
	var sy := 0.0285
	var slide := pivot(r, Vector3.ZERO)
	box(slide, Vector3(0.025, 0.027, 0.19), s, Vector3(0, 0.0085, -0.07))
	for i in 6:
		for sx: float in [-1.0, 1.0]:
			box(slide, Vector3(0.001, 0.02, 0.003), mat("port"), Vector3(sx * 0.0126, 0.009, 0.014 - i * 0.006))
	box(slide, Vector3(0.012, 0.0012, 0.026), mat("port"), Vector3(0.003, 0.0222, -0.04))
	var trit := glow("tritium", Color(0.35, 1.0, 0.45), 1.6)
	post(slide, sy, -0.158, 0.0036, 0.022, false, s)
	box(slide, Vector3(0.0017, 0.0017, 0.001), trit, Vector3(0, sy - 0.0022, -0.1556))
	box(slide, Vector3(0.022, 0.0018, 0.009), s, Vector3(0, 0.0229, 0.013))
	notch(slide, sy, 0.016, 0.0046, 0.0042, 0.0085, 0.0228, s)
	for sx: float in [-1.0, 1.0]:
		box(slide, Vector3(0.0017, 0.0017, 0.001), trit, Vector3(sx * 0.0066, sy - 0.0024, 0.0181))
	box(r, Vector3(0.023, 0.016, 0.16), p, Vector3(0, -0.013, -0.065))
	box(r, Vector3(0.006, 0.004, 0.044), p, Vector3(0, -0.047, -0.012))
	box(r, Vector3(0.006, 0.03, 0.004), p, Vector3(0, -0.034, -0.034))
	box(r, Vector3(0.003, 0.014, 0.004), s, Vector3(0, -0.03, -0.004))
	box(r, Vector3(0.028, 0.1, 0.046), p, Vector3(0, -0.068, 0.03), Vector3(-0.28, 0, 0))
	lathe(r, [Vector2(-0.33, 0.0), Vector2(-0.33, 0.0145), Vector2(-0.325, 0.0165), Vector2(-0.18, 0.0165), Vector2(-0.172, 0.011), Vector2(-0.165, 0.007), Vector2(-0.165, 0.0)], s, Vector3.ZERO, 20)
	var mag := pivot(r, Vector3(0, -0.028, 0.022), Vector3(-0.28, 0, 0))
	box(mag, Vector3(0.022, 0.1, 0.034), s, Vector3(0, -0.05, 0))
	box(mag, Vector3(0.03, 0.011, 0.05), p, Vector3(0, -0.105, 0.0))
	var hand := grip_hand(r, Vector3(0, -0.07, 0.03), -0.28, Vector3(0.08, -0.26, 0.32))
	hand.position.x += 0.002
	var lh := pivot(r, Vector3(-0.026, -0.07, 0.028), Vector3(-0.28, 0, 0))
	var g := mat("glove")
	box(lh, Vector3(0.016, 0.07, 0.05), g, Vector3(0, 0, 0))
	for i in 3:
		box(lh, Vector3(0.05, 0.016, 0.018), mat("glove_pad"), Vector3(0.024, -0.016 - i * 0.018, -0.036))
	box(lh, Vector3(0.012, 0.012, 0.05), g, Vector3(0.002, 0.03, -0.03), Vector3(0.1, 0, 0))
	var e := lh.basis.inverse() * Vector3(-0.1, -0.24, 0.32)
	limb(lh, Vector3(-0.004, -0.02, 0.03), e, 0.066, 0.064, mat("sleeve"))
	limb(lh, e, e + Vector3(-0.05, -0.1, 0.25), 0.08, 0.08, mat("sleeve"))
	var rig := _rig(r, sy, 0.36, 0.016, Vector3(0.1, -0.11, -0.36))
	rig.merge({"mag": mag, "bolt": slide, "bolt_travel": Vector3(0, 0, 0.042), "cycles": true, "slide_lock": true, "muzzle": Vector3(0, 0, -0.335), "eject": Vector3(0.016, 0.02, -0.04), "lhand": lh, "case": "pistol"})
	return rig


func _ar7() -> Dictionary:
	var r := Node3D.new()
	var s := mat("bluing")
	var w := mat("wood")
	var sy := 0.05
	box(r, Vector3(0.03, 0.044, 0.24), s, Vector3(0, -0.006, 0.0))
	lathe(r, [Vector2(-0.11, 0.0), Vector2(-0.11, 0.0148), Vector2(0.115, 0.0148), Vector2(0.125, 0.0), ], s, Vector3(0, 0.008, 0), 16)
	box(r, Vector3(0.0015, 0.012, 0.06), mat("port"), Vector3(0.0153, 0.004, -0.04))
	box(r, Vector3(0.0025, 0.009, 0.075), s, Vector3(0.0162, -0.004, 0.025))
	box(r, Vector3(0.022, 0.026, 0.05), s, Vector3(0, 0.019, -0.138))
	box(r, Vector3(0.02, 0.005, 0.07), s, Vector3(0, 0.0345, -0.115), Vector3(0.04, 0, 0))
	notch(r, sy, -0.146, 0.0032, 0.003, 0.0075, 0.037, s)
	cyl(r, 0.0088, 0.22, s, Vector3(0, 0.022, -0.27), 12)
	cyl(r, 0.0135, 0.12, w, Vector3(0, 0.021, -0.235), 12)
	box(r, Vector3(0.044, 0.038, 0.17), w, Vector3(0, -0.013, -0.245))
	box(r, Vector3(0.046, 0.008, 0.012), s, Vector3(0, -0.013, -0.33))
	cyl(r, 0.0085, 0.36, s, Vector3(0, 0, -0.3))
	box(r, Vector3(0.017, 0.022, 0.024), s, Vector3(0, 0.012, -0.43))
	post(r, sy, -0.43, 0.0026, 0.023, true, s)
	lathe(r, [Vector2(-0.505, 0.0), Vector2(-0.505, 0.0095), Vector2(-0.48, 0.0115), Vector2(-0.48, 0.0)], s, Vector3.ZERO, 10)
	box(r, Vector3(0.028, 0.086, 0.036), w, Vector3(0, -0.066, 0.045), Vector3(-0.3, 0, 0))
	box(r, Vector3(0.006, 0.004, 0.06), s, Vector3(0, -0.045, 0.0))
	box(r, Vector3(0.04, 0.072, 0.25), w, Vector3(0, -0.03, 0.245), Vector3(0.12, 0, 0))
	box(r, Vector3(0.042, 0.095, 0.012), s, Vector3(0, -0.047, 0.37), Vector3(0.12, 0, 0))
	var mag := pivot(r, Vector3(0, -0.03, -0.075))
	box(mag, Vector3(0.024, 0.06, 0.068), s, Vector3(0, -0.028, 0), Vector3(0.15, 0, 0))
	box(mag, Vector3(0.024, 0.058, 0.066), s, Vector3(0, -0.083, -0.016), Vector3(0.36, 0, 0))
	box(mag, Vector3(0.024, 0.055, 0.064), s, Vector3(0, -0.132, -0.042), Vector3(0.58, 0, 0))
	box(mag, Vector3(0.028, 0.012, 0.07), s, Vector3(0, -0.158, -0.06), Vector3(0.62, 0, 0))
	var bolt := pivot(r, Vector3(0.021, 0.004, -0.07))
	box(bolt, Vector3(0.016, 0.009, 0.011), s, Vector3(0.004, 0, 0))
	grip_hand(r, Vector3(0, -0.066, 0.047), -0.3)
	var lh := support_hand(r, Vector3(0, -0.006, -0.25), 0.024)
	var rig := _rig(r, sy, 0.3, -0.146, Vector3(0.155, -0.16, -0.31))
	rig.merge({"mag": mag, "bolt": bolt, "bolt_travel": Vector3(0, 0, 0.085), "cycles": true, "muzzle": Vector3(0, 0, -0.505), "eject": Vector3(0.02, 0.006, -0.04), "lhand": lh, "case": "steel"})
	return rig


func _lmg() -> Dictionary:
	var r := Node3D.new()
	var p := mat("poly")
	var s := mat("bluing")
	var sy := 0.075
	box(r, Vector3(0.048, 0.07, 0.3), s, Vector3(0, -0.01, 0.0))
	box(r, Vector3(0.0015, 0.018, 0.05), mat("port"), Vector3(0.0245, -0.01, -0.03))
	var cover := pivot(r, Vector3(0, 0.025, 0.05))
	box(cover, Vector3(0.058, 0.024, 0.16), s, Vector3(0, 0.011, -0.08))
	box(cover, Vector3(0.03, 0.012, 0.028), s, Vector3(0, 0.028, 0.0))
	peep(cover, sy - 0.025, 0.006, 0.034)
	box(r, Vector3(0.05, 0.04, 0.18), p, Vector3(0, -0.03, -0.24))
	cyl(r, 0.011, 0.5, s, Vector3(0, 0, -0.38))
	box(r, Vector3(0.03, 0.004, 0.24), s, Vector3(0, 0.017, -0.29))
	box(r, Vector3(0.028, 0.028, 0.04), s, Vector3(0, -0.018, -0.46))
	box(r, Vector3(0.018, 0.04, 0.016), s, Vector3(0, 0.026, -0.56))
	post(r, sy, -0.56, 0.003, 0.046, true, s)
	lathe(r, [Vector2(-0.68, 0.0), Vector2(-0.68, 0.0125), Vector2(-0.63, 0.0135), Vector2(-0.63, 0.0)], s, Vector3.ZERO, 8)
	box(r, Vector3(0.012, 0.014, 0.12), p, Vector3(-0.034, 0.03, -0.27))
	for sx: float in [-1.0, 1.0]:
		cyl(r, 0.0042, 0.26, s, Vector3(sx * 0.012, -0.052, -0.45), 8)
	box(r, Vector3(0.032, 0.09, 0.04), p, Vector3(0, -0.085, 0.07), Vector3(-0.3, 0, 0))
	box(r, Vector3(0.046, 0.09, 0.25), p, Vector3(0, -0.03, 0.29))
	var mag := pivot(r, Vector3(-0.012, -0.045, -0.035))
	box(mag, Vector3(0.07, 0.11, 0.13), mat("od"), Vector3(-0.016, -0.058, 0))
	box(mag, Vector3(0.074, 0.012, 0.134), mat("cuff"), Vector3(-0.016, -0.004, 0))
	box(mag, Vector3(0.022, 0.006, 0.04), mat("brass"), Vector3(0.025, 0.052, 0.0))
	var bolt := pivot(r, Vector3(0.029, 0.0, -0.08))
	box(bolt, Vector3(0.02, 0.012, 0.012), s, Vector3(0.006, 0, 0))
	grip_hand(r, Vector3(0, -0.085, 0.072), -0.3)
	var lh := support_hand(r, Vector3(0, -0.03, -0.25), 0.026)
	var rig := _rig(r, sy, 0.13, 0.056, Vector3(0.165, -0.18, -0.36))
	rig.merge({"mag": mag, "bolt": bolt, "bolt_travel": Vector3(0, 0, 0.1), "cycles": false, "muzzle": Vector3(0, 0, -0.68), "eject": Vector3(0.026, -0.01, -0.03), "lhand": lh, "case": "rifle", "cover": cover})
	return rig


func _shotgun() -> Dictionary:
	var r := Node3D.new()
	var p := mat("poly")
	var s := mat("bluing")
	var sy := 0.0195
	box(r, Vector3(0.032, 0.054, 0.2), s, Vector3(0, -0.0115, -0.01))
	box(r, Vector3(0.0035, 0.0006, 0.2), mat("port"), Vector3(0, 0.0156, -0.01))
	box(r, Vector3(0.0015, 0.019, 0.055), mat("port"), Vector3(0.0162, -0.004, -0.04))
	box(r, Vector3(0.022, 0.0015, 0.06), mat("port"), Vector3(0, -0.0385, -0.04))
	cyl(r, 0.0105, 0.47, s, Vector3(0, 0, -0.345))
	box(r, Vector3(0.008, 0.0035, 0.46), s, Vector3(0, 0.0125, -0.345))
	for i in 9:
		box(r, Vector3(0.004, 0.004, 0.006), s, Vector3(0, 0.0095, -0.13 - i * 0.05))
	sphere(r, 0.0036, glow("bead", Color(1.0, 0.6, 0.25), 1.1), Vector3(0, sy - 0.0036, -0.572))
	cyl(r, 0.011, 0.41, s, Vector3(0, -0.026, -0.315))
	lathe(r, [Vector2(-0.53, 0.0), Vector2(-0.53, 0.008), Vector2(-0.52, 0.0125), Vector2(-0.51, 0.0125), Vector2(-0.51, 0.0)], s, Vector3(0, -0.026, 0), 12)
	box(r, Vector3(0.006, 0.022, 0.06), s, Vector3(0, -0.049, 0.035))
	box(r, Vector3(0.034, 0.05, 0.12), p, Vector3(0, -0.03, 0.135), Vector3(0.25, 0, 0))
	box(r, Vector3(0.04, 0.11, 0.21), p, Vector3(0, -0.072, 0.27), Vector3(0.12, 0, 0))
	box(r, Vector3(0.042, 0.12, 0.02), mat("rubber"), Vector3(0, -0.086, 0.38), Vector3(0.12, 0, 0))
	var pump := pivot(r, Vector3(0, -0.028, -0.25))
	box(pump, Vector3(0.042, 0.036, 0.14), p, Vector3.ZERO)
	for i in 6:
		box(pump, Vector3(0.044, 0.003, 0.008), mat("rubber"), Vector3(0, -0.006, -0.05 + i * 0.02))
	cyl(pump, 0.003, 0.17, s, Vector3(0.012, 0.012, 0.11), 6)
	var lh := support_hand(pump, Vector3(0, 0.0, 0.0), 0.021)
	var shell := pivot(r, Vector3(0, -0.06, -0.05))
	cyl(shell, 0.0105, 0.055, mat("hull"), Vector3(0, 0, 0.0))
	cyl(shell, 0.011, 0.012, mat("brass"), Vector3(0, 0, 0.033))
	shell.visible = false
	var hand := grip_hand(r, Vector3(0, -0.035, 0.085), 0.25, Vector3(0.15, -0.3, 0.3))
	hand.position.y -= 0.004
	var rig := _rig(r, sy, 0.12, 0.09, Vector3(0.155, -0.16, -0.33))
	rig.merge({"mag": shell, "bolt": pump, "bolt_travel": Vector3(0, 0, 0.075), "cycles": false, "muzzle": Vector3(0, 0, -0.585), "eject": Vector3(0.02, -0.004, -0.04), "lhand": lh, "case": "shell", "pump": true})
	return rig
