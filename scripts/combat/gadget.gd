class_name Gadget
extends RigidBody3D
## Thrown equipment: frag, flashbang, smoke and noisemaker. Physics handles the bounce;
## the effect fires when the fuse runs out.

signal detonated(gadget: Gadget)

const INFO := {
	"frag": {"name": "FRAG", "fuse": 3.0, "color": Color("3a4a30"), "radius": 4.0},
	"flash": {"name": "FLASHBANG", "fuse": 1.6, "color": Color("8a9096"), "radius": 0.0},
	"smoke": {"name": "SMOKE", "fuse": 1.5, "color": Color("4a5a64"), "radius": 4.5},
	"decoy": {"name": "NOISEMAKER", "fuse": 1.0, "color": Color("b08030"), "radius": 0.0},
	"extinguisher": {"name": "EXTINGUISHER", "fuse": 0.5, "color": Color("a81e1e"), "radius": 3.2},
}

var type := "frag"
var owner_is_player := true
var fuse := 3.0
var live := false
var life := 0.0
var age := 0.0
var tick := 0.0
var cloud_radius := 0.0
var fog: FogVolume
var puffs: GPUParticles3D
var _last_speed := 0.0


static func create(p_type: String, from_player: bool) -> Gadget:
	var g := Gadget.new()
	g.type = p_type
	g.owner_is_player = from_player
	g.fuse = INFO[p_type].fuse
	g.collision_layer = Layers.GADGETS
	g.collision_mask = Layers.WORLD
	g.mass = 0.4
	g.continuous_cd = true
	g.contact_monitor = true
	g.max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	g.physics_material_override = pm
	g.angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.06
	cs.shape = sh
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	if p_type == "frag":
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		mi.mesh = sm
	elif p_type == "decoy":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.06, 0.07)
		mi.mesh = bm
	elif p_type == "extinguisher":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.075
		cm.height = 0.46
		mi.mesh = cm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.045
		cm.height = 0.13
		mi.mesh = cm
	mi.material_override = Mats.plain(INFO[p_type].color, 0.6, 0.3)
	g.add_child(mi)
	g.body_entered.connect(g._on_hit)
	return g


func _on_hit(_body: Node) -> void:
	if _last_speed > 2.0:
		Sfx.play_at("bounce", global_position, -4.0)


## Called by the game every physics tick. Returns false once the gadget is spent.
func step(dt: float) -> bool:
	_last_speed = linear_velocity.length()
	if not live:
		fuse -= dt
		if fuse <= 0.0:
			detonated.emit(self)
			if type == "frag" or type == "flash":
				return false
			live = true
			life = 22.0 if type == "smoke" else (11.0 if type == "extinguisher" else 7.0)
			if is_cloud():
				_start_smoke()
		return true
	life -= dt
	age += dt
	tick -= dt
	if is_cloud():
		var rmax := 4.8 if type == "smoke" else 3.2
		cloud_radius = minf(rmax, 0.8 + age * 2.2) if life > 4.0 else rmax * life / 4.0
		var mat := fog.material as FogMaterial
		mat.density = clampf(cloud_radius / rmax, 0.0, 1.0) * 2.5
		fog.size = Vector3.ONE * cloud_radius * 2.0 * Vector3(1.0, 0.6, 1.0)
		fog.global_position = global_position + Vector3.UP * cloud_radius * 0.45
		var pm := puffs.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = maxf(0.5, cloud_radius * 0.7)
		puffs.emitting = life > 5.0
		puffs.global_position = global_position + Vector3.UP * cloud_radius * 0.35
		if tick <= 0.0 and life > 4.0:
			Sfx.play_at("hiss", global_position, -6.0)
			tick = 2.0
	return life > 0.0


## Smoke grenades and extinguishers both fill a volume you can't see through.
func is_cloud() -> bool:
	return type == "smoke" or type == "extinguisher"


func _start_smoke() -> void:
	fog = FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	var fm := FogMaterial.new()
	fm.albedo = Color("9aa0a6")
	fm.emission = Color(0.04, 0.045, 0.05)
	fm.density = 0.0
	fm.edge_fade = 0.6
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var tex := NoiseTexture3D.new()
	tex.noise = noise
	tex.width = 32
	tex.height = 32
	tex.depth = 32
	fm.density_texture = tex
	fog.material = fm
	get_parent().add_child(fog)
	puffs = GPUParticles3D.new()
	puffs.amount = 140
	puffs.lifetime = 7.0
	puffs.preprocess = 0.0
	puffs.explosiveness = 0.25
	puffs.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 12, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.5
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.12, 0)
	pm.damping_min = 0.6
	pm.damping_max = 0.9
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.62, 0.64, 0.0))
	grad.add_point(0.12, Color(0.6, 0.62, 0.64, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.6, 0.62, 0.64, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	puffs.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.roughness = 1.0
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	var quad := QuadMesh.new()
	quad.size = Vector2(4.2, 4.2)
	quad.material = mat
	puffs.draw_pass_1 = quad
	get_parent().add_child(puffs)
	puffs.global_position = global_position + Vector3.UP * 0.5


## Where the smoke blocks sight (centre, radius); radius 0 when inactive.
func smoke_sphere() -> Vector4:
	if not is_cloud() or not live:
		return Vector4.ZERO
	var c := global_position + Vector3.UP * cloud_radius * 0.45
	return Vector4(c.x, c.y, c.z, cloud_radius)


func _exit_tree() -> void:
	if fog and is_instance_valid(fog):
		fog.queue_free()
	if puffs and is_instance_valid(puffs):
		puffs.queue_free()
