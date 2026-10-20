extends Node

## 背景音乐与环境音。
##
## 全局一首无缝循环 OGG（assets/audio/bgm/main_theme.ogg），三章共用；另有一层很轻的风声 ambience.ogg。
## 曲子由真录音片段拼成（古琴/古筝/箫/埙/铜钟/战鼓/锣/山风），不再走 tools/generate_bgm.py。
## 旧版运行时那套 55Hz 拍频嗡鸣已整段删掉——它就是「听久了生理不适」的来源。
## 走单独的 Music 总线，「音乐音量」滑条才管得着；环境音层也走这条总线，另外受「背景音效」开关控制。
##
## 换界面靠每帧看一眼 GameManager.current_screen，不另发信号：音乐该跟的是「现在人在哪个界面」，
## 而不是「谁调用了 change_screen」——读档、测试、以后新加的入口走别的路进来也一样跟得上。

const BGM_DIR: String = "res://assets/audio/bgm/"
## 三章共用同一首；保留三个槽位是为了不改章节索引。三个槽拿到的是同一份缓存流，
## 换章时 _crossfade 只会淡回目标音量，不会从头重播。
const CHAPTER_TRACKS: Array[String] = ["main_theme", "main_theme", "main_theme"]
const AMBIENT_TRACK: String = "ambience"

## 换曲时先淡出、再换、再淡入。硬切会在接缝处「咔」一声，而且两首曲子调性不同，接缝很扎耳。
const FADE_SECONDS: float = 0.6
## 淡出之后停在这个音量，已经小到听不见，不用真的负无穷。
const SILENT_DB: float = -40.0

## 曲子的母带已经压到 RMS -20dBFS，这里再让一点，垫在音效下面去。
const BGM_LEVEL_DB: float = -3.5
## 风声已经录得很轻（RMS -26dBFS），再压低一层，它是氛围不是内容。
const AMBIENT_LEVEL_DB: float = -10.0

var _bgm: AudioStreamPlayer = null
var _ambient: AudioStreamPlayer = null
var _cache: Dictionary = {}
## 每个播放器一份淡入淡出的补间，换曲时要先把上一次的掐掉，不然两个补间会同时改音量。
var _fades: Dictionary = {}
var _screen: int = -1
var _chapter: int = -1
var _ambient_on: bool = false
var _first: bool = true


func _ready() -> void:
	_bgm = _make_player()
	_ambient = _make_player()
	_apply(true)


func _process(_delta: float) -> void:
	_apply(false)


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	# 挂到 Music 总线上，「音乐音量」滑条才管得着（主音量管所有总线）。
	player.bus = SettingsManager.MUSIC_BUS
	player.volume_db = SILENT_DB
	add_child(player)
	return player


## 设定改了就立刻重来一遍，不用等下一帧——滑条和勾选框拖起来才跟手。
func refresh() -> void:
	_apply(true)


func _apply(force: bool) -> void:
	var screen: int = GameManager.current_screen
	var chapter: int = _chapter_for(screen)
	var ambient_on: bool = SettingsManager.ambient
	if not force and screen == _screen and chapter == _chapter and ambient_on == _ambient_on:
		return

	var screen_changed := screen != _screen or _first
	var chapter_changed := chapter != _chapter
	_screen = screen
	_chapter = chapter
	_ambient_on = ambient_on
	_first = false

	# 同一首曲子接着放，别从头重来——原地重放会「咔」一下，也没必要。
	if screen_changed or chapter_changed or _bgm.stream == null:
		_crossfade(_bgm, _load_loop(CHAPTER_TRACKS[chapter - 1]), BGM_LEVEL_DB)

	if not ambient_on or not _ambient_active(screen):
		_crossfade(_ambient, null, AMBIENT_LEVEL_DB)
	elif screen_changed or _ambient.stream == null:
		_crossfade(_ambient, _load_loop(AMBIENT_TRACK), AMBIENT_LEVEL_DB)


# --- 哪个界面放哪首 ---

## 局内（地图/战斗/商店/休息/奖励/事件）一律跟本局章号走，进新章自动换曲。
## 菜单和选人还没开局，用第一章的主题；胜利固定收在第三章。
func _chapter_for(screen: int) -> int:
	match screen:
		GameManager.GameScreen.MAIN_MENU, GameManager.GameScreen.CHARACTER_SELECT:
			return 1
		GameManager.GameScreen.VICTORY:
			return CHAPTER_TRACKS.size()
	return clampi(GameManager.current_chapter, 1, CHAPTER_TRACKS.size())


## 环境风声只在局内垫底，菜单上不加。
func _ambient_active(screen: int) -> bool:
	match screen:
		GameManager.GameScreen.MAIN_MENU, GameManager.GameScreen.CHARACTER_SELECT, \
				GameManager.GameScreen.GAME_OVER, GameManager.GameScreen.VICTORY:
			return false
	return true


# --- 换曲 ---

## 传 null 表示把这一路淡出停掉。
## 曲子已经在放就直接淡回来（比如「背景音效」关了又开），不从头重来。
func _crossfade(player: AudioStreamPlayer, stream: AudioStream, target_db: float) -> void:
	_kill_fade(player)
	if stream == null:
		_fades[player] = _fade(player, SILENT_DB, player.stop)
		return

	if player.playing and player.stream == stream:
		_fades[player] = _fade(player, target_db)
		return

	if not player.playing:
		player.stream = stream
		player.volume_db = SILENT_DB
		player.play()
		_fades[player] = _fade(player, target_db)
		return

	# 正在放别的：先淡掉，换流，再淡起来。
	var tween := create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		player.stream = stream
		player.play())
	tween.tween_property(player, "volume_db", target_db, FADE_SECONDS)
	_fades[player] = tween


func _fade(player: AudioStreamPlayer, to_db: float, on_done: Callable = Callable()) -> Tween:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, FADE_SECONDS)
	if on_done.is_valid():
		tween.tween_callback(on_done)
	return tween


func _kill_fade(player: AudioStreamPlayer) -> void:
	var running: Variant = _fades.get(player)
	if running is Tween and (running as Tween).is_valid():
		(running as Tween).kill()


# --- 载入 ---

## 循环点是按「整段绕回开头」设计的，所以直接开 loop，不需要淡入淡出接缝。
func _load_loop(track_name: String) -> AudioStream:
	if _cache.has(track_name):
		return _cache[track_name]
	var path := BGM_DIR + track_name + ".ogg"
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("MusicManager: 找不到 %s" % path)
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_cache[track_name] = stream
	return stream
