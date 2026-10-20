class_name AudioClips
extends RefCounted

## 音效文件的取用口。跟 `ArtIcons` 同一族：数据/调用方只给 key，能不能取到由这里判。
## **缺音频不是错误状态**——取不到就返 null，`EffectsManager` 各自退回原来的合成音。

const SFX_DIR := "res://assets/audio/sfx/"
## 优先级顺序：wav 优先（无损、且确认过 loop_mode 关得掉），其次 ogg，最后 mp3。
const EXTS := [".wav", ".ogg", ".mp3"]


## 取不到就返 null。
##
## **两道判断都得有**：`ResourceLoader.exists()` 返 true 而 `load()` 返 null 是真会发生的
## ——`.import` 在仓库里而 `.godot/imported/` 里的 blob 还没导出来时就是这样。
## 音频这边一样会撞（跟 [[bugfix-texture-expand-mode-blows-anchors]] 同族的「声明值≠实测值」）。
##
## **返回类型必须是 `AudioStream` 不能写 `AudioStreamWAV`**：文件换成 ogg/mp3 时写死类型会崩。
##
## **刻意不缓存**（同 `ArtIcons`）：缓存 null 会在「刚落完音频还没重启」时骗人。
static func load_or_null(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


static func _pick(key: String) -> AudioStream:
	for ext in EXTS:
		var stream := load_or_null(SFX_DIR + key + ext)
		if stream != null:
			return stream
	return null


## 能取到时给路径，否则空串。给断言/排查看「到底命中了哪个扩展名」。
static func sfx_path(key: String) -> String:
	var stream := _pick(key)
	return "" if stream == null else stream.resource_path


static func load_sfx_or_null(key: String) -> AudioStream:
	return _pick(key)
