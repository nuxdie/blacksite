class_name Mats
## Shared surface materials. Penetration resistance (cost per metre of travel) lives here too:
## a material missing from PEN stops every bullet.

const SURFACE := preload("res://shaders/surface.gdshader")

const DEFS := {
	"asphalt": {"color": Color("3b3c3e"), "pattern": 5, "rough": 0.95, "grime": 0.3},
	"concrete": {"color": Color("8b8a86"), "pattern": 6, "rough": 0.9, "grime": 0.35},
	"block": {"color": Color("7b7771"), "pattern": 1, "rough": 0.95, "grime": 0.4},
	"corrugated": {"color": Color("8d969e"), "pattern": 2, "rough": 0.6, "metal": 0.4, "grime": 0.45},
	"roof": {"color": Color("3a3e44"), "pattern": 2, "rough": 0.7, "metal": 0.3},
	"plaster": {"color": Color("b3ad9f"), "pattern": 0, "rough": 0.95, "grime": 0.25, "bump": 0.3},
	"wood": {"color": Color("8a6a42"), "pattern": 3, "rough": 0.85, "grime": 0.2},
	"grating": {"color": Color("55585c"), "pattern": 4, "rough": 0.6, "metal": 0.5, "grime": 0.2},
	"metal": {"color": Color("55585c"), "pattern": 0, "rough": 0.55, "metal": 0.5, "grime": 0.3},
	"rack": {"color": Color("d8661a"), "pattern": 0, "rough": 0.6, "metal": 0.3, "grime": 0.3},
	"steel": {"color": Color("8a9096"), "pattern": 0, "rough": 0.45, "metal": 0.6, "grime": 0.25},
	"c_red": {"color": Color("8a2a20"), "pattern": 2, "rough": 0.7, "metal": 0.35, "grime": 0.45},
	"c_blue": {"color": Color("24486e"), "pattern": 2, "rough": 0.7, "metal": 0.35, "grime": 0.45},
	"c_green": {"color": Color("2f5a36"), "pattern": 2, "rough": 0.7, "metal": 0.35, "grime": 0.45},
	"c_rust": {"color": Color("8a5426"), "pattern": 2, "rough": 0.75, "metal": 0.3, "grime": 0.5},
	"glass": {"color": Color("101418"), "pattern": 0, "rough": 0.08, "metal": 0.6, "grime": 0.1},
	"dirt": {"color": Color("3a352c"), "pattern": 5, "rough": 1.0, "grime": 0.5},
	"paint": {"color": Color("c8a640"), "pattern": 0, "rough": 0.9, "grime": 0.2},
}

const PEN := {
	"plaster": 1.0, "wood": 0.75, "glass": 0.1, "corrugated": 0.6, "roof": 0.6, "metal": 1.6,
	"c_red": 0.2, "c_blue": 0.2, "c_green": 0.2, "c_rust": 0.2,
}

# Materials that ring like metal when hit.
const METALLIC := ["corrugated", "roof", "metal", "rack", "steel", "grating", "c_red", "c_blue", "c_green", "c_rust"]

static var _cache: Dictionary = {}


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	if key == "glass":
		# real glass: see-through with a faint cold tint and a hard reflective face
		var g := StandardMaterial3D.new()
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.albedo_color = Color(0.62, 0.74, 0.82, 0.2)
		g.metallic = 0.4
		g.roughness = 0.04
		g.metallic_specular = 0.8
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = g
		return g
	var d: Dictionary = DEFS.get(key, DEFS["concrete"])
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("albedo", d["color"])
	m.set_shader_parameter("pattern", d["pattern"])
	m.set_shader_parameter("roughness_base", d.get("rough", 0.85))
	m.set_shader_parameter("metallic_base", d.get("metal", 0.0))
	m.set_shader_parameter("grime", d.get("grime", 0.35))
	m.set_shader_parameter("bump", d.get("bump", 1.0))
	_cache[key] = m
	return m


static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func plain(color: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
