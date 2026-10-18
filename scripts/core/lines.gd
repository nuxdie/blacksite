class_name Lines
extends RefCounted
## The spoken-line catalogue (assets/voice/lines.json): one source for subtitles and audio.
## Guards' lines come in six voices; a guard's voice follows their call order, and a callsign
## therefore always answers radio checks in the same voice.

const PATH := "res://assets/voice/lines.json"

static var _data: Dictionary = {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_data = {"guard": {}, "hq": {}, "security": {}, "callsigns": [], "voices": {"guards": ["g0"], "hq": "hq", "security": "sec"}}
		return
	_data = JSON.parse_string(f.get_as_text())


static func guard(kind: String) -> Array:
	_load()
	return (_data.guard as Dictionary).get(kind, [])


static func hq(kind: String) -> Array:
	_load()
	return (_data.hq as Dictionary).get(kind, [])


static func security(kind: String) -> Array:
	_load()
	return (_data.security as Dictionary).get(kind, [])


static func callsigns() -> Array:
	_load()
	return _data.get("callsigns", [])


static func guard_voices() -> Array:
	_load()
	return _data.voices.guards


static func guard_voice(call_order: int) -> String:
	var v := guard_voices()
	return v[call_order % v.size()]


static func hq_voice() -> String:
	_load()
	return _data.voices.hq


static func security_voice() -> String:
	_load()
	return _data.voices.security


## File-name form of a callsign or device label: "Gate 2" -> "gate_2", "CAM 03" -> "cam_03".
static func slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")
