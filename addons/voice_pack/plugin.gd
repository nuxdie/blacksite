@tool
extends EditorPlugin
## assets/voice is .gdignore'd so the editor doesn't import four hundred ogg files, which also
## keeps the folder out of exports. This export plugin walks the real folder and adds each file
## to the pack as-is, at its res:// path, so FileAccess and AudioStreamOggVorbis.load_from_file
## find them in a shipped build exactly as they do in the editor.

const ROOT := "res://assets/voice"

var _packer := VoicePacker.new()


func _enter_tree() -> void:
	add_export_plugin(_packer)


func _exit_tree() -> void:
	remove_export_plugin(_packer)


class VoicePacker:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "VoicePack"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var n := _add_dir(ROOT)
		print("VoicePack: packed %d files from %s" % [n, ROOT])

	func _add_dir(dir: String) -> int:
		var d := DirAccess.open(dir)
		if d == null:
			return 0
		var n := 0
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var p := dir.path_join(name)
			if d.current_is_dir():
				n += _add_dir(p)
			elif not name.begins_with("."):
				add_file(p, FileAccess.get_file_as_bytes(p), false)
				n += 1
			name = d.get_next()
		d.list_dir_end()
		return n
