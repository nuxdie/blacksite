class_name Lamp
extends Node3D
## A light fixture that can be shot out. Lit areas make the player easier to spot.

var light: OmniLight3D
var fixture: MeshInstance3D
var fixture_mat: StandardMaterial3D
var energy := 1.0
var light_range := 12.0
var dead := false
var flickers := false
## Lighting circuit, switched at that zone's breaker panel.
var zone := ""
var powered := true
var _flicker_t := 0.0


func setup(color: Color, p_energy: float, p_range: float, cool: bool, p_flickers := false) -> void:
	energy = p_energy * 2.2
	light_range = p_range
	flickers = p_flickers
	fixture_mat = Mats.emissive(Color("e0ecff") if cool else Color("ffb060"), 6.0 if cool else 7.0)
	fixture = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.06, 0.3)
	fixture.mesh = bm
	fixture.material_override = fixture_mat
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixture)
	light = OmniLight3D.new()
	light.position = Vector3(0, -0.25, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.0
	light.shadow_enabled = true
	light.shadow_bias = 0.06
	light.light_volumetric_fog_energy = 2.2
	add_child(light)


func _process(delta: float) -> void:
	if dead or not powered or not flickers:
		return
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(0.03, 0.4)
		var on := randf() > 0.25
		light.light_energy = energy if on else 0.0
		fixture_mat.emission_energy_multiplier = 6.0 if on else 0.3


func is_lit() -> bool:
	return not dead and powered and light.light_energy > 0.0


## How much this lamp lights a point (0..1).
func contribution(p: Vector3) -> float:
	if not is_lit():
		return 0.0
	var d := global_position.distance_to(p)
	var r := light_range * 0.7
	return 0.0 if d > r else (1.0 - d / r)


## Breaker cut: the circuit goes dark without a sound.
func power_off() -> void:
	powered = false
	light.visible = false
	fixture_mat.emission_energy_multiplier = 0.0


func power_on() -> void:
	powered = true
	if dead:
		return
	light.visible = true
	light.light_energy = energy
	fixture_mat.emission_energy_multiplier = 6.0


func shatter() -> void:
	if dead:
		return
	dead = true
	light.light_energy = 0.0
	light.visible = false
	fixture_mat.emission_energy_multiplier = 0.0
	Sfx.play_at("glass", global_position)
