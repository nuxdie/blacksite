extends Node
## Sound bank and playback. Every sound is synthesized once and cached in user://.
## World sounds are positional, filtered by distance and muffled behind walls.

const CACHE_DIR := "user://sfx_cache_v3/"
const WORLD_POOL := 28
const FLAT_POOL := 10

var bank: Dictionary = {}
var _world: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _wi := 0
var _fi := 0
var _lowpass: AudioEffectLowPassFilter
var _muffle := 0.0


func _n(dur: float, vol: float, filter: String, f0: float, f1 := -1.0, q := 0.7, at := 0.0, attack := 0.002) -> Dictionary:
	return {"type": "noise", "dur": dur, "vol": vol, "filter": filter, "f0": f0, "f1": f0 if f1 < 0.0 else f1, "q": q, "at": at, "attack": attack}


func _t(type: String, f0: float, f1: float, dur: float, vol: float, at := 0.0, attack := 0.003) -> Dictionary:
	return {"type": type, "f0": f0, "f1": f1, "dur": dur, "vol": vol, "at": at, "attack": attack}


func _defs() -> Dictionary:
	return {
		"rifle": [_n(0.07, 0.9, "hp", 1800), _n(0.32, 0.8, "lp", 3500, 300), _t("sine", 160, 45, 0.14, 0.8)],
		"dmr": [_n(0.09, 1.0, "hp", 1500), _n(0.7, 0.9, "lp", 3000, 140), _t("sine", 120, 32, 0.28, 1.0)],
		"sd": [_n(0.11, 0.45, "lp", 1300, 300), _t("sine", 120, 60, 0.06, 0.3), _n(0.03, 0.18, "hp", 4000, -1, 0.7, 0.01)],
		"sd_smg": [_n(0.09, 0.4, "lp", 1800, 350), _t("sine", 150, 60, 0.05, 0.25), _n(0.03, 0.15, "hp", 4500, -1, 0.7, 0.01)],
		"enemy_rifle": [_n(0.06, 0.7, "hp", 1600), _n(0.3, 0.7, "lp", 3000, 260), _t("sine", 150, 40, 0.14, 0.6)],
		"enemy_lmg": [_n(0.06, 0.75, "hp", 1200), _n(0.32, 0.75, "lp", 2600, 220), _t("sine", 120, 40, 0.14, 0.65)],
		"enemy_shotgun": [_n(0.4, 1.0, "lp", 3000, 200), _t("sine", 120, 40, 0.2, 0.8)],
		"whizz": [_n(0.14, 0.5, "bp", 5000, 1500, 4.0), _t("sine", 2400, 900, 0.1, 0.06)],
		"impact": [_n(0.08, 0.45, "bp", 2400, 1600, 1.5), _n(0.03, 0.2, "hp", 3000)],
		"impact_metal": [_n(0.06, 0.35, "bp", 3000, 2200, 3.0), _t("tri", 2600, 2100, 0.12, 0.08)],
		"flesh": [_n(0.1, 0.5, "lp", 900, 200), _t("sine", 110, 60, 0.08, 0.4)],
		"helmet": [_t("tri", 2600, 1800, 0.12, 0.18), _n(0.05, 0.4, "hp", 3000)],
		"hit": [_t("square", 340, 280, 0.04, 0.05)],
		"hit_head": [_t("tri", 1500, 1900, 0.07, 0.09)],
		"kill": [_t("sine", 220, 90, 0.12, 0.12)],
		"dry": [_t("square", 900, 700, 0.025, 0.06)],
		"mag_out": [_t("square", 700, 500, 0.03, 0.06), _n(0.06, 0.12, "bp", 1800, -1, 3.0)],
		"mag_in": [_t("square", 500, 400, 0.04, 0.08), _n(0.05, 0.18, "bp", 1200, -1, 3.0)],
		"bolt": [_n(0.05, 0.2, "bp", 2500, -1, 4.0), _t("square", 1100, 800, 0.03, 0.06, 0.08), _n(0.05, 0.2, "bp", 3000, -1, 4.0, 0.09)],
		"step": [_n(0.07, 0.6, "lp", 800, 180)],
		"enemy_step": [_n(0.08, 0.7, "lp", 900, 200)],
		"land": [_n(0.12, 0.6, "lp", 600, 100)],
		"cloth": [_n(0.15, 0.25, "bp", 900, 600, 1.0)],
		"drag": [_n(0.35, 0.3, "lp", 500, 250)],
		"breath_in": [_n(0.5, 0.2, "bp", 500, 900, 1.0, 0.0, 0.2)],
		"breath_out": [_n(0.7, 0.22, "bp", 700, 400, 1.0, 0.0, 0.1)],
		"radio": [_n(0.09, 0.25, "bp", 2500, -1, 2.0), _t("square", 1400, 1400, 0.05, 0.05, 0.05)],
		"throw": [_n(0.2, 0.25, "bp", 600, 1800, 2.0)],
		"pin": [_t("tri", 3200, 2800, 0.06, 0.08)],
		"bounce": [_t("tri", 2200, 1500, 0.07, 0.15)],
		"explode": [_n(1.4, 1.0, "lp", 2000, 60), _t("sine", 80, 22, 1.0, 1.0), _n(0.1, 0.7, "hp", 1500)],
		"bang": [_n(0.12, 1.0, "hp", 1200), _n(0.9, 0.9, "lp", 4000, 200), _t("sine", 1800, 600, 0.2, 0.3)],
		"ring": [_t("sine", 3500, 3400, 3.5, 0.06, 0.0, 0.05)],
		"hiss": [_n(2.1, 0.18, "hp", 2600, -1, 0.7, 0.0, 0.1)],
		"decoy": [_t("square", 900, 500, 0.05, 0.12), _n(0.08, 0.3, "bp", 1900, -1, 3.0, 0.06)],
		"glass": [_n(0.35, 0.5, "hp", 3500), _t("tri", 4200, 4200, 0.12, 0.06), _t("tri", 3100, 3100, 0.12, 0.06, 0.04), _t("tri", 4800, 4800, 0.12, 0.05, 0.08)],
		"tag": [_t("tri", 1200, 1600, 0.08, 0.07)],
		"hurt": [_n(0.2, 0.4, "lp", 900, 150), _t("sine", 90, 50, 0.15, 0.4)],
		"heart": [_t("sine", 55, 40, 0.12, 0.4), _t("sine", 50, 38, 0.12, 0.3, 0.18)],
		"pickup": [_t("tri", 700, 1100, 0.1, 0.08)],
		"takedown": [_n(0.25, 0.5, "lp", 1200, 200), _t("sine", 90, 40, 0.2, 0.5)],
		"body": [_n(0.25, 0.4, "lp", 500, 80, 0.7, 0.3)],
		"objective": [_t("tri", 660, 660, 0.15, 0.12), _t("tri", 990, 990, 0.3, 0.12, 0.15)],
		"truck": [_t("saw", 50, 70, 2.5, 0.2, 0.0, 0.8), _n(2.5, 0.2, "lp", 300, -1, 0.7, 0.0, 0.8)],
		"ui_move": [_t("tri", 1400, 1500, 0.03, 0.04)],
		"ui_select": [_t("tri", 900, 1300, 0.07, 0.07)],
		"hint": [_t("sine", 1200, 1200, 0.05, 0.04), _t("sine", 1600, 1600, 0.08, 0.04, 0.05)],
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_bank()
	for i in WORLD_POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.unit_size = 4.0
		p.max_distance = 90.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_world.append(p)
	for i in FLAT_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Player"
		add_child(p)
		_flat.append(p)
	_start_ambience()


func _setup_buses() -> void:
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	for bus_name: String in ["World", "Player", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	var verb := AudioEffectReverb.new()
	verb.room_size = 0.75
	verb.damping = 0.6
	verb.wet = 0.18
	verb.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), verb)
	var pverb := AudioEffectReverb.new()
	pverb.room_size = 0.6
	pverb.wet = 0.1
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Player"), pverb)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), -12.0)


func _build_bank() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var defs := _defs()
	for key: String in defs:
		var path := CACHE_DIR + key + ".res"
		if ResourceLoader.exists(path):
			bank[key] = load(path)
			continue
		var wav := Synth.render(defs[key])
		ResourceSaver.save(wav, path)
		bank[key] = wav


func _start_ambience() -> void:
	var path := CACHE_DIR + "amb_wind.res"
	var wind: AudioStreamWAV
	if ResourceLoader.exists(path):
		wind = load(path)
	else:
		wind = Synth.render([_n(6.0, 0.35, "lp", 380, 260, 0.7), _t("sine", 58, 58, 6.0, 0.05)], true, 6.0)
		ResourceSaver.save(wind, path)
	var p := AudioStreamPlayer.new()
	p.stream = wind
	p.bus = "Ambience"
	add_child(p)
	p.play()


## Non-positional sound (your own weapon, UI, heartbeat).
func play(key: String, vol_db := 0.0, pitch_var := 0.05) -> void:
	if not bank.has(key):
		return
	var p := _flat[_fi]
	_fi = (_fi + 1) % FLAT_POOL
	p.stream = bank[key]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Positional sound. Muffled when a wall stands between it and the listener.
func play_at(key: String, pos: Vector3, vol_db := 0.0, occlude := true, pitch_var := 0.06) -> void:
	if not bank.has(key):
		return
	var p := _world[_wi]
	_wi = (_wi + 1) % WORLD_POOL
	p.stream = bank[key]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	var cutoff := 9000.0
	var cam := get_viewport().get_camera_3d()
	if occlude and cam and cam.global_position.distance_to(pos) > 2.0:
		var space := cam.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos, cam.global_position, 1)
		if not space.intersect_ray(q).is_empty():
			cutoff = 750.0
			p.volume_db -= 5.0
	p.attenuation_filter_cutoff_hz = cutoff
	p.play()


## 0 = clear hearing, 1 = deafened (suppression, flashbangs).
func set_muffle(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if absf(amount - _muffle) < 0.01:
		return
	_muffle = amount
	_lowpass.cutoff_hz = lerpf(20000.0, 500.0, pow(amount, 0.6))
