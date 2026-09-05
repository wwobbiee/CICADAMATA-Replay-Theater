class_name ReplayFile
extends RefCounted

# Wraps a saved ghost replay file & a JSON sidecar so a replay
#		can be shared as a pair of files: <name>.res + <name>.replaymeta.json
# This does NOT touch ghost.gd's recording, it just resuses the Animation
#		object it already builds i.e `ghostanim' and gives it a persistant,
#		shared home instead of always overwriting Ghosts/<level>.res
const REPLAY_SUBDIR := "Replays/"
const FORMAT_VERSION := 1


static func save(anim: Animation, level_id: String, save_root: String, player_name: String = "Player") -> String:
	var dir := save_root + REPLAY_SUBDIR
	DirAccess.make_dir_recursive_absolute(dir)

	var timestamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var base_name := "%s_%s" % [level_id, timestamp]
	var res_path := dir + base_name + ".res"

	anim.compress(8192, 12)
	var err := ResourceSaver.save(anim, res_path)
	if err != OK:
		push_error("ReplayFile.save: Failed to save %s (err %d)" % [res_path, err])
		return ""

	var meta := {
		"level": level_id,
		"player": player_name,
		"length": anim.length,
		"created": Time.get_datetime_string_from_system(true).replace(":", "-"),
		"format_version": FORMAT_VERSION
	}

	var meta_path := dir + base_name + ".replaymeta.json"
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()

	return res_path

static func list_available(save_root: String) -> Array:
	var dir_path := save_root + REPLAY_SUBDIR
	var results: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return results

	var dir := DirAccess.open(dir_path)
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".replaymeta.json"):
			var f := FileAccess.open(dir_path + file_name, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()

			if parsed:
				parsed["res_path"] = dir_path + file_name.replace(".replaymeta.json", ".res")
				results.append(parsed)
		file_name = dir.get_next()
	dir.list_dir_end()

	return results

static func load_animation(res_path: String) -> Animation:
	if not ResourceLoader.exists(res_path):
		push_error("ReplayFile.load_animation: no file at %s" % res_path)
		return null

	return ResourceLoader.load(res_path, "Animation", ResourceLoader.CACHE_MODE_REPLACE)

static func import_shared_pair(res_source_path: String, meta_source_path: String, save_root: String) -> String:
	var dir := save_root + REPLAY_SUBDIR
	DirAccess.make_dir_recursive_absolute(dir)

	var base_name := res_source_path.get_file().get_basename()
	var res_dest := dir + base_name + ".res"
	var meta_dest := dir + base_name + ".replaymeta.json"

	DirAccess.copy_absolute(res_source_path, res_dest)

	if FileAccess.file_exists(meta_source_path):
		DirAccess.copy_absolute(meta_source_path, meta_dest)

	return res_dest
