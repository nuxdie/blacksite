extends Node
## Sound bank and playback. Every effect is synthesized once and cached in user://; voices are
## rendered lines under assets/voice (see tools/voices/render.py).
##
## Buses: World (positional, reverb), Player (your own gear), Voice (people and radios), UI (cues
## that exist only for you), Ambience (wind, interiors, tension beds).
##
## Besides one-shots there are named loops (loop_at / stop_loop) for anything that keeps going,
## and two state channels the game drives every frame: tension(), the bed under the mix that says
## whether you are noticed or hunted, and interior(), which swaps wind for ventilation indoors.

const CACHE_DIR := "user://sfx_cache_v5/"
const VOICE_DIR := "res://assets/voice/"
const WORLD_POOL := 28
const FLAT_POOL := 10
const VOICE_POOL := 8
const SILENT := -60.0

var bank: Dictionary = {}
var _world: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _wi := 0
var _fi := 0
var _ui_i := 0
var _vi := 0
var _lowpass: AudioEffectLowPassFilter
var _muffle := 0.0
## id -> {player, target_db, rate}
var _loops: Dictionary = {}
var _beds: Dictionary = {}
var _tension := 0.0
var _interior := 0.0
var _voice_cache: Dictionary = {}
var _voice_missing: Dictionary = {}
var _radio_busy_t := 0.0


func _n(dur: float, vol: float, filter: String, f0: float, f1 := -1.0, q := 0.7, at := 0.0, attack := 0.002) -> Dictionary:
	return {"type": "noise", "dur": dur, "vol": vol, "filter": filter, "f0": f0, "f1": f0 if f1 < 0.0 else f1, "q": q, "at": at, "attack": attack}


func _t(type: String, f0: float, f1: float, dur: float, vol: float, at := 0.0, attack := 0.003) -> Dictionary:
	return {"type": type, "f0": f0, "f1": f1, "dur": dur, "vol": vol, "at": at, "attack": attack}


## Extra envelope/modulation keys on a layer.
func _m(layer: Dictionary, extra: Dictionary) -> Dictionary:
	layer.merge(extra, true)
	return layer


func _defs() -> Dictionary:
	return {
		# --- weapons and impacts
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
		"dry": [_t("square", 900, 700, 0.025, 0.06)],
		"mag_out": [_t("square", 700, 500, 0.03, 0.06), _n(0.06, 0.12, "bp", 1800, -1, 3.0)],
		"mag_in": [_t("square", 500, 400, 0.04, 0.08), _n(0.05, 0.18, "bp", 1200, -1, 3.0)],
		"bolt": [_n(0.05, 0.2, "bp", 2500, -1, 4.0), _t("square", 1100, 800, 0.03, 0.06, 0.08), _n(0.05, 0.2, "bp", 3000, -1, 4.0, 0.09)],
		"selector": [_t("square", 1500, 1200, 0.02, 0.08), _n(0.02, 0.1, "bp", 3000, -1, 2.0, 0.02)],
		"weapon_pickup": [_n(0.05, 0.4, "bp", 1500, -1, 1.5), _t("square", 400, 300, 0.04, 0.15), _n(0.04, 0.2, "bp", 2500, -1, 2.0, 0.07)],
		# --- movement and body
		"step": [_n(0.07, 0.6, "lp", 800, 180)],
		"enemy_step": [_n(0.08, 0.7, "lp", 900, 200)],
		"land": [_n(0.12, 0.6, "lp", 600, 100)],
		"cloth": [_n(0.15, 0.25, "bp", 900, 600, 1.0)],
		"drag": [_n(0.35, 0.3, "lp", 500, 250)],
		"breath_in": [_n(0.5, 0.2, "bp", 500, 900, 1.0, 0.0, 0.2)],
		"breath_out": [_n(0.7, 0.22, "bp", 700, 400, 1.0, 0.0, 0.1)],
		"hurt": [_n(0.2, 0.4, "lp", 900, 150), _t("sine", 90, 50, 0.15, 0.4)],
		"hurt_breath": [_n(0.4, 0.25, "bp", 800, 500, 1.2, 0.0, 0.05)],
		"heart": [_t("sine", 55, 40, 0.12, 0.4), _t("sine", 50, 38, 0.12, 0.3, 0.18)],
		"bleed": [_t("sine", 200, 90, 0.08, 0.12), _n(0.03, 0.1, "lp", 1200)],
		"medkit": [_n(0.25, 0.2, "bp", 2500, 4000, 2.0), _t("tri", 700, 700, 0.05, 0.05, 0.26)],
		"takedown": [_n(0.25, 0.5, "lp", 1200, 200), _t("sine", 90, 40, 0.2, 0.5)],
		"body": [_n(0.25, 0.4, "lp", 500, 80, 0.7, 0.3)],
		"pickup": [_t("tri", 700, 1100, 0.1, 0.08)],
		# --- equipment
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
		# --- the site: doors, devices, power, radios
		"radio": [_n(0.09, 0.25, "bp", 2500, -1, 2.0), _t("square", 1400, 1400, 0.05, 0.05, 0.05)],
		"radio_open": [_n(0.09, 0.3, "bp", 2200, -1, 1.5, 0.0, 0.004), _t("square", 1600, 1600, 0.02, 0.05)],
		"radio_close": [_t("square", 1200, 1200, 0.015, 0.05), _n(0.06, 0.2, "bp", 2500, -1, 1.5, 0.01)],
		"hq_tone": [_m(_t("tri", 1100, 1100, 0.1, 0.07), {"hold": 0.7}), _m(_t("tri", 1100, 1100, 0.1, 0.07, 0.16), {"hold": 0.7})],
		"door": [_n(0.55, 0.25, "bp", 700, 400, 1.5), _t("saw", 90, 70, 0.5, 0.05)],
		"deny": [_t("square", 520, 520, 0.08, 0.05), _t("square", 380, 380, 0.12, 0.05, 0.1)],
		"badge_ok": [_m(_t("tri", 2100, 2100, 0.06, 0.07), {"hold": 0.7}), _m(_t("tri", 2600, 2600, 0.09, 0.07, 0.07), {"hold": 0.6})],
		"maglock": [_t("square", 90, 60, 0.06, 0.3), _n(0.08, 0.4, "lp", 900, 300)],
		"breaker": [_t("square", 120, 80, 0.08, 0.3), _n(0.1, 0.4, "lp", 800, 200)],
		"power_down": [_t("saw", 110, 30, 0.9, 0.15), _n(0.8, 0.2, "lp", 1500, 100)],
		"power_up": [_t("saw", 40, 110, 0.6, 0.12), _t("square", 1200, 1200, 0.02, 0.05, 0.6)],
		"comms_cut": [_m(_n(0.5, 0.2, "hp", 2000), {"trem": 40.0, "trem_d": 0.9}), _t("square", 3000, 200, 0.3, 0.08)],
		"comms_up": [_n(0.15, 0.2, "bp", 2500, -1, 1.5), _t("tri", 1400, 1400, 0.05, 0.06, 0.15)],
		"cam_dead": [_t("square", 2000, 100, 0.4, 0.06), _n(0.1, 0.1, "bp", 3000, -1, 2.0)],
		"cam_notice": [_m(_t("sine", 1800, 1800, 0.05, 0.05), {"hold": 0.8}), _m(_t("sine", 1800, 1800, 0.05, 0.05, 0.1), {"hold": 0.8})],
		"drone_scan": [_t("sine", 2400, 2000, 0.1, 0.06)],
		"drone_lock": [_m(_t("square", 1800, 1800, 0.08, 0.05), {"hold": 0.8}), _m(_t("square", 1800, 1800, 0.08, 0.05, 0.12), {"hold": 0.8}), _m(_t("square", 1800, 1800, 0.08, 0.05, 0.24), {"hold": 0.8})],
		"drone_down": [_m(_t("saw", 220, 40, 1.2, 0.15), {"vib": 9.0, "vib_d": 0.04}), _n(1.0, 0.15, "lp", 2000, 200)],
		"emp": [_t("sine", 60, 60, 0.3, 0.3), _n(0.4, 0.2, "hp", 6000), _t("saw", 3000, 200, 0.3, 0.1)],
		"flashlight": [_t("square", 2600, 2200, 0.015, 0.08), _n(0.02, 0.1, "bp", 3000, -1, 2.0)],
		"truck": [_t("saw", 50, 70, 2.5, 0.2, 0.0, 0.8), _n(2.5, 0.2, "lp", 300, -1, 0.7, 0.0, 0.8)],
		"truck_door": [_n(0.12, 0.5, "lp", 700, 200), _t("sine", 90, 60, 0.12, 0.3)],
		"alarm": [_t("square", 1250, 1250, 0.14, 0.1), _t("square", 900, 900, 0.14, 0.1, 0.2), _t("square", 1250, 1250, 0.14, 0.1, 0.4), _t("square", 900, 900, 0.14, 0.1, 0.6)],
		"siren": [_t("tri", 520, 1020, 0.8, 0.22, 0.0, 0.05), _t("tri", 1020, 520, 0.8, 0.22, 0.8, 0.02), _t("square", 520, 1020, 0.8, 0.03, 0.0, 0.05)],
		"objective": [_t("tri", 660, 660, 0.15, 0.12), _t("tri", 990, 990, 0.3, 0.12, 0.15)],
		# --- the terminal
		"key": [_n(0.015, 0.15, "bp", 3500, -1, 2.0), _t("tri", 2500, 2500, 0.01, 0.05)],
		"term_login": [_t("tri", 1200, 1200, 0.06, 0.06), _t("tri", 1600, 1600, 0.08, 0.06, 0.08), _t("tri", 2000, 2000, 0.12, 0.06, 0.16)],
		"term_ok": [_m(_t("tri", 1500, 1500, 0.05, 0.06), {"hold": 0.6})],
		"term_err": [_t("square", 300, 300, 0.12, 0.05), _t("square", 250, 250, 0.12, 0.05, 0.13)],
		"term_trace": [_m(_t("square", 2200, 2200, 0.06, 0.05), {"hold": 0.7}), _m(_t("square", 2200, 2200, 0.06, 0.05, 0.12), {"hold": 0.7})],
		"term_kick": [_t("square", 400, 200, 0.5, 0.12), _n(0.3, 0.15, "hp", 3000)],
		# --- cues that exist only for you
		"ui_move": [_t("tri", 1400, 1500, 0.03, 0.04)],
		"ui_select": [_t("tri", 900, 1300, 0.07, 0.07)],
		"hint": [_t("sine", 1200, 1200, 0.05, 0.04), _t("sine", 1600, 1600, 0.08, 0.04, 0.05)],
		"toast": [_t("tri", 1800, 1700, 0.02, 0.05)],
		"banner": [_n(0.35, 0.12, "lp", 400, 1200, 0.7, 0.0, 0.1), _t("sine", 220, 220, 0.3, 0.08)],
		"save": [_t("tri", 880, 880, 0.06, 0.06), _t("tri", 1320, 1320, 0.1, 0.06, 0.07)],
		"load": [_t("tri", 1320, 1320, 0.06, 0.06), _t("tri", 880, 880, 0.1, 0.06, 0.07)],
		"pause": [_t("square", 600, 600, 0.03, 0.04)],
		"notice": [_t("sine", 900, 1300, 0.12, 0.07)],
		"unnotice": [_t("sine", 1300, 800, 0.14, 0.05)],
		"spotted": [_t("sine", 120, 50, 0.25, 0.5), _n(0.05, 0.3, "hp", 2000), _t("tri", 1800, 1800, 0.05, 0.1)],
		"lost_you": [_t("sine", 1000, 1000, 0.08, 0.05), _t("sine", 750, 750, 0.12, 0.05, 0.09)],
		"extracted": [_t("tri", 523, 523, 0.6, 0.08), _t("tri", 659, 659, 0.6, 0.08, 0.1), _t("tri", 784, 784, 0.8, 0.08, 0.2), _t("tri", 1046, 1046, 1.0, 0.08, 0.3)],
		"death": [_t("sine", 80, 30, 2.0, 0.5), _n(2.0, 0.3, "lp", 300, 60)],
	}


## Looping sounds: key -> [layers, seconds].
func _loop_defs() -> Dictionary:
	return {
		"drone_hum": [[_t("saw", 150, 150, 1.0, 0.06, 0.0, 0.05), _t("saw", 226, 226, 1.0, 0.04, 0.0, 0.05), _n(1.0, 0.03, "bp", 1800, -1, 2.0)], 1.0],
		"amb_wind": [[_n(6.0, 0.35, "lp", 380, 260, 0.7), _t("sine", 58, 58, 6.0, 0.05)], 6.0],
		"amb_interior": [[_n(6.0, 0.2, "lp", 500, 500), _m(_t("saw", 120, 120, 6.0, 0.02), {"trem": 0.3, "trem_d": 0.3}), _t("sine", 60, 60, 6.0, 0.04)], 6.0],
		"bed_notice": [[_m(_t("sine", 220, 220, 4.0, 0.05), {"trem": 0.5, "trem_d": 0.5}), _m(_t("sine", 331, 331, 4.0, 0.03), {"trem": 0.37, "trem_d": 0.6}), _m(_n(4.0, 0.012, "bp", 3000, -1, 2.0), {"trem": 0.7, "trem_d": 0.8})], 4.0],
		"bed_hunt": [[_m(_t("sine", 55, 55, 4.0, 0.12), {"trem": 2.0, "trem_d": 0.8}), _m(_t("saw", 110, 110, 4.0, 0.03), {"trem": 2.0, "trem_d": 0.8}), _m(_t("sine", 82.4, 82.4, 4.0, 0.05), {"trem": 1.0, "trem_d": 0.5}), _m(_n(4.0, 0.06, "lp", 200), {"trem": 2.0, "trem_d": 0.8})], 4.0],
		"term_hum": [[_t("saw", 60, 60, 1.0, 0.03), _n(1.0, 0.01, "bp", 8000, -1, 2.0)], 1.0],
		"splice_loop": [[_m(_n(1.0, 0.12, "bp", 5000, -1, 3.0), {"trem": 17.0, "trem_d": 0.9}), _m(_t("saw", 100, 100, 1.0, 0.02), {"trem": 17.0, "trem_d": 0.9})], 1.0],
		"clone_loop": [[_m(_t("tri", 2400, 2400, 1.0, 0.03), {"trem": 9.0, "trem_d": 1.0}), _n(1.0, 0.01, "bp", 6000, -1, 2.0)], 1.0],
		"work_loop": [[_m(_n(1.0, 0.08, "bp", 1800, -1, 2.0), {"trem": 6.0, "trem_d": 0.8})], 1.0],
		"vent_loop": [[_m(_n(1.0, 0.1, "bp", 2500, -1, 3.0), {"trem": 4.0, "trem_d": 0.9}), _m(_t("tri", 900, 900, 1.0, 0.01), {"trem": 4.0, "trem_d": 0.9})], 1.0],
		"relay_loop": [[_m(_t("saw", 120, 120, 1.0, 0.04), {"trem": 30.0, "trem_d": 0.7}), _m(_n(1.0, 0.06, "hp", 5000), {"trem": 13.0, "trem_d": 0.9})], 1.0],
		"copy_loop": [[_m(_n(1.0, 0.05, "bp", 4000, -1, 4.0), {"trem": 11.0, "trem_d": 1.0}), _m(_t("sine", 7000, 7000, 1.0, 0.01), {"trem": 3.0, "trem_d": 0.8})], 1.0],
		"cam_servo": [[_m(_t("saw", 85, 85, 1.0, 0.025), {"trem": 40.0, "trem_d": 0.3}), _n(1.0, 0.02, "bp", 1200, -1, 2.0)], 1.0],
		"motor": [[_t("saw", 48, 48, 1.0, 0.04), _m(_t("saw", 96, 96, 1.0, 0.02), {"trem": 25.0, "trem_d": 0.2}), _n(1.0, 0.03, "lp", 400)], 1.0],
	}


## Level trims applied at render time, so each cue lands where it belongs in the mix: interface
## cues and tones just above the noise floor, machines audible from a few metres, beds felt.
const GAIN := {
	"cam_servo": 8.0, "motor": 4.0, "copy_loop": 5.0, "clone_loop": 5.0, "work_loop": 4.0, "vent_loop": 3.0, "term_hum": 5.0,
	"bed_notice": 2.5, "bed_hunt": 1.6,
	"badge_ok": 3.0, "maglock": 1.5, "cam_notice": 3.0, "cam_dead": 2.0, "drone_lock": 5.0, "drone_scan": 2.5, "flashlight": 2.0,
	"power_up": 2.5, "hq_tone": 2.2, "key": 2.0, "term_login": 2.5, "term_ok": 2.0, "term_err": 4.0, "term_trace": 5.0, "deny": 3.0,
	"bleed": 1.6, "hurt_breath": 2.0, "selector": 2.5, "notice": 2.2, "unnotice": 2.5, "lost_you": 2.5, "toast": 2.0, "pause": 5.0,
	"save": 2.0, "load": 2.0, "banner": 1.8, "hint": 2.0, "ui_move": 1.5, "radio_close": 1.4, "drone_down": 1.5, "comms_up": 1.6,
}


func _trim(key: String, layers: Array) -> Array:
	var g: float = GAIN.get(key, 1.0)
	if g == 1.0:
		return layers
	var out := []
	for l: Dictionary in layers:
		var c := l.duplicate()
		c.vol = float(c.vol) * g
		out.append(c)
	return out


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
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui.append(p)
	for i in VOICE_POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Voice"
		p.unit_size = 5.0
		p.max_distance = 70.0
		p.attenuation_filter_db = -14.0
		add_child(p)
		_voices.append(p)
	_start_ambience()
	apply_volumes()


func _setup_buses() -> void:
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	for bus_name: String in ["World", "Player", "Voice", "UI", "Ambience"]:
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
	var vverb := AudioEffectReverb.new()
	vverb.room_size = 0.7
	vverb.damping = 0.7
	vverb.wet = 0.12
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Voice"), vverb)


## Settings sliders are 0..1; silence below a few percent.
func apply_volumes() -> void:
	_bus_vol("Master", Settings.vol_master, 0.0)
	_bus_vol("World", Settings.vol_effects, 0.0)
	_bus_vol("Player", Settings.vol_effects, 0.0)
	_bus_vol("UI", Settings.vol_effects, -4.0)
	_bus_vol("Voice", Settings.vol_voice, 0.0)
	_bus_vol("Ambience", Settings.vol_ambience, -10.0)


func _bus_vol(bus_name: String, k: float, base_db: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, base_db + (linear_to_db(k) if k > 0.02 else -80.0))


func _build_bank() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var defs := _defs()
	for key: String in defs:
		var path := CACHE_DIR + key + ".res"
		if ResourceLoader.exists(path):
			bank[key] = load(path)
			continue
		var wav := Synth.render(_trim(key, defs[key]))
		ResourceSaver.save(wav, path)
		bank[key] = wav
	var loops := _loop_defs()
	for key: String in loops:
		var path := CACHE_DIR + key + ".res"
		if ResourceLoader.exists(path):
			bank[key] = load(path)
			continue
		var wav := Synth.render(_trim(key, loops[key][0]), true, loops[key][1])
		ResourceSaver.save(wav, path)
		bank[key] = wav


func _start_ambience() -> void:
	for key: String in ["amb_wind", "amb_interior", "bed_notice", "bed_hunt"]:
		var p := AudioStreamPlayer.new()
		p.stream = bank[key]
		p.bus = "Ambience"
		p.volume_db = 0.0 if key == "amb_wind" else SILENT
		add_child(p)
		p.play()
		_beds[key] = p


func _process(dt: float) -> void:
	_radio_busy_t = maxf(0.0, _radio_busy_t - dt)
	# ambience: wind outside, ventilation inside
	_beds["amb_wind"].volume_db = lerpf(0.0, -14.0, _interior)
	_beds["amb_interior"].volume_db = lerpf(SILENT, 0.0, _interior) if _interior > 0.02 else SILENT
	# tension beds
	var notice := clampf(_tension, 0.0, 1.0) * clampf(2.0 - _tension, 0.0, 1.0)
	var hunt := clampf(_tension - 1.0, 0.0, 1.0)
	_beds["bed_notice"].volume_db = lerpf(SILENT, -3.0, notice) if notice > 0.02 else SILENT
	_beds["bed_hunt"].volume_db = lerpf(SILENT, 0.0, hunt) if hunt > 0.02 else SILENT
	# named loops ease toward their targets and stop when silent
	for id in _loops.keys():
		var l: Dictionary = _loops[id]
		var p: Node = l.player
		var target: float = l.target
		var cur: float = p.volume_db
		p.volume_db = move_toward(cur, target, dt * float(l.rate))
		if target <= SILENT and p.volume_db <= SILENT + 0.5:
			p.queue_free()
			_loops.erase(id)


## 0 = quiet, 1 = someone is noticing you, 2 = you are hunted. Eases over a second or two.
func tension(level: float, dt: float) -> void:
	_tension = move_toward(_tension, clampf(level, 0.0, 2.0), dt * (1.5 if level > _tension else 0.4))


## 0 = outdoors, 1 = inside a building.
func interior(k: float, dt: float) -> void:
	_interior = move_toward(_interior, clampf(k, 0.0, 1.0), dt * 1.2)


# ------------------------------------------------------------------ one-shots

## Non-positional sound (your own weapon, breathing, heartbeat).
func play(key: String, vol_db := 0.0, pitch_var := 0.05) -> void:
	if not bank.has(key):
		return
	var p := _flat[_fi]
	_fi = (_fi + 1) % FLAT_POOL
	p.stream = bank[key]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Interface cue: exists only for you, never in the world.
func ui(key: String, vol_db := 0.0) -> void:
	if not bank.has(key):
		return
	var p := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	p.stream = bank[key]
	p.volume_db = vol_db
	p.pitch_scale = 1.0
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
	p.attenuation_filter_cutoff_hz = 750.0 if (occlude and occluded(pos)) else 9000.0
	if p.attenuation_filter_cutoff_hz < 1000.0:
		p.volume_db -= 5.0
	p.play()


func occluded(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(pos) < 2.0:
		return false
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos, cam.global_position, 1)
	return not space.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ loops

## Keep a looping sound running at a place; call every frame it should continue. Starts it the
## first time, and moves/retargets it after that.
func loop_at(id: String, key: String, pos: Vector3, vol_db := 0.0, unit_size := 3.0, max_distance := 30.0) -> void:
	if not _loops.has(id):
		if not bank.has(key):
			return
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.stream = bank[key]
		p.unit_size = unit_size
		p.max_distance = max_distance
		p.attenuation_filter_db = -18.0
		p.volume_db = SILENT
		add_child(p)
		p.play()
		_loops[id] = {"player": p, "target": vol_db, "rate": 80.0}
	var l: Dictionary = _loops[id]
	l.target = vol_db
	var p3: AudioStreamPlayer3D = l.player
	p3.global_position = pos
	p3.attenuation_filter_cutoff_hz = 750.0 if occluded(pos) else 9000.0


## A flat loop (the terminal hum while you are connected).
func loop(id: String, key: String, vol_db := 0.0) -> void:
	if not _loops.has(id):
		if not bank.has(key):
			return
		var p := AudioStreamPlayer.new()
		p.bus = "Player"
		p.stream = bank[key]
		p.volume_db = SILENT
		add_child(p)
		p.play()
		_loops[id] = {"player": p, "target": vol_db, "rate": 80.0}
	_loops[id].target = vol_db


func stop_loop(id: String, fade_rate := 60.0) -> void:
	if _loops.has(id):
		_loops[id].target = SILENT
		_loops[id].rate = fade_rate


func loop_running(id: String) -> bool:
	return _loops.has(id) and float(_loops[id].target) > SILENT


# ------------------------------------------------------------------ voices

## Path of a rendered line, or "" if it was never rendered.
func voice_path(voice: String, kind: String, index: int, slug := "", radio := false) -> String:
	var name := "%s_%d" % [kind, index]
	if slug != "":
		name += "_" + slug
	var path := "%s%s/%s%s.ogg" % [VOICE_DIR, voice, name, ".r" if radio else ""]
	if _voice_missing.has(path):
		return ""
	if not _voice_cache.has(path) and not FileAccess.file_exists(path):
		_voice_missing[path] = true
		return ""
	return path


func _voice_stream(path: String) -> AudioStream:
	if _voice_cache.has(path):
		return _voice_cache[path]
	var s := AudioStreamOggVorbis.load_from_file(path)
	_voice_cache[path] = s
	return s


## Speak a line at a place. Radio lines open with a squelch and close with a click. Returns the
## player so the speaker can be cut off mid-sentence, and the clip length through `out`.
func speak(path: String, pos: Vector3, radio: bool, vol_db := 0.0, occlude := true) -> AudioStreamPlayer3D:
	if path == "":
		return null
	var stream := _voice_stream(path)
	if stream == null:
		return null
	var p := _voices[_vi]
	_vi = (_vi + 1) % VOICE_POOL
	p.stop()
	p.stream = stream
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-0.025, 0.025)
	p.attenuation_filter_cutoff_hz = 9000.0
	if occlude and not radio and occluded(pos):
		p.attenuation_filter_cutoff_hz = 900.0
		p.volume_db -= 6.0
	if radio:
		play_at("radio_open", pos, vol_db - 6.0, false, 0.0)
		var len := stream.get_length()
		get_tree().create_timer(0.14).timeout.connect(func() -> void:
			if p.stream == stream:
				p.play())
		get_tree().create_timer(0.14 + len + 0.05).timeout.connect(func() -> void:
			if p.stream == stream:
				play_at("radio_close", p.global_position, vol_db - 8.0, false, 0.0))
	else:
		p.play()
	return p


func voice_length(path: String) -> float:
	if path == "":
		return 0.0
	var s := _voice_stream(path)
	return s.get_length() if s else 0.0


## 0 = clear hearing, 1 = deafened (suppression, flashbangs).
func set_muffle(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if absf(amount - _muffle) < 0.01:
		return
	_muffle = amount
	_lowpass.cutoff_hz = lerpf(20000.0, 500.0, pow(amount, 0.6))
