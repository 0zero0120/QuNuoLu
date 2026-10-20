class_name RunHistory
extends Resource

## 对局历史，单独存一个文件——每条记录带着牌组和遗物清单，不能塞进每层都在重写的 meta_progress.json。
const SAVE_PATH: String = "user://run_history.json"
const MAX_RECORDS: int = 50

## 分数权重，想调手感直接改这里。
const SCORE_WEIGHTS := {
	"floor": 5,
	"enemy": 1,
	"boss": 10,
	"gold": 0.1,
	"relic": 5,
	"card": 2,
	"victory": 500,
}

@export var records: Array[Dictionary] = []

func to_dict() -> Dictionary:
	var out: Array = []
	for record in records:
		out.append(record)
	return {"records": out}

func from_dict(data: Dictionary) -> void:
	var raw: Variant = data.get("records", [])
	records.clear()
	if raw is Array:
		for entry: Variant in raw:
			if typeof(entry) == TYPE_DICTIONARY:
				records.append(entry)

func append(record: Dictionary) -> void:
	records.insert(0, record)
	while records.size() > MAX_RECORDS:
		records.pop_back()

func size() -> int:
	return records.size()

func is_empty() -> bool:
	return records.is_empty()

func get_record(index: int) -> Dictionary:
	if index < 0 or index >= records.size():
		return {}
	return records[index]

## 收集到的不同类型的数量，历史页的「遗物 (n)」之类用得上。
func count_of(record: Dictionary, key: String) -> int:
	var raw: Variant = record.get(key, [])
	return raw.size() if raw is Array else 0

## score = 楼层×5 + 击杀数 + 首领数×10 + 金币/10 + 遗物数×5 + 牌组张数×2 + 通关 500
static func compute_score(snapshot: Dictionary) -> int:
	var w := SCORE_WEIGHTS
	var total := 0.0
	total += int(snapshot.get("floor", 0)) * int(w["floor"])
	total += int(snapshot.get("enemies_killed", 0)) * int(w["enemy"])
	total += int(snapshot.get("bosses_killed", 0)) * int(w["boss"])
	total += int(snapshot.get("gold", 0)) * float(w["gold"])
	total += _array_len(snapshot.get("relic_ids", [])) * int(w["relic"])
	total += _array_len(snapshot.get("deck_card_ids", [])) * int(w["card"])
	if bool(snapshot.get("victory", false)):
		total += int(w["victory"])
	return int(round(total))

static func _array_len(raw: Variant) -> int:
	return raw.size() if raw is Array else 0

# --- 落盘 ---

## 读失败时返回一份空历史，但绝不回写覆盖原文件（照抄 GameManager._read_save_dict 的守卫思路）。
static func load_from_disk() -> RunHistory:
	var history := RunHistory.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return history
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return history
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[RunHistory] %s 解析失败，本次按空历史处理（不覆盖原文件）" % SAVE_PATH)
		return history
	history.from_dict(parsed as Dictionary)
	return history

## 临时文件 + rename，避免写一半崩掉留下半个文件。
## Windows 上 rename 不能覆盖已存在的目标，所以先删目标再改名。
func save_to_disk() -> void:
	var target := ProjectSettings.globalize_path(SAVE_PATH)
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[RunHistory] 无法写入 %s" % tmp)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()

	var dir := DirAccess.open(ProjectSettings.globalize_path("user://"))
	if dir == null:
		push_error("[RunHistory] 无法打开 user:// 目录")
		return
	if dir.file_exists(target):
		dir.remove_absolute(target)
	var err := dir.rename_absolute(tmp, target)
	if err != OK:
		push_error("[RunHistory] rename 失败 err=%d (%s -> %s)" % [err, tmp, target])
