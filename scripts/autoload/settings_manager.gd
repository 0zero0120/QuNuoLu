extends Node

## 全局设定：画面、声音、偏好，以及按键绑定。
## 落盘在 user://settings.cfg，用引擎自带的 ConfigFile（键位直接按输入事件存，不用自己拼字符串）。
## 开局读一次并立刻应用；之后每次改动都当场生效并写盘。

const SAVE_PATH: String = "user://settings.cfg"

## 音效和音乐各走一条总线，好让「音效音量」和「音乐音量」互不干扰（主音量管所有总线）。
const SFX_BUS: String = "SFX"
const MUSIC_BUS: String = "Music"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const RESOLUTION_LABELS: Array[String] = [
	"1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440",
]
const DEFAULT_RESOLUTION_INDEX: int = 2

## 0 表示不限帧。
const FPS_OPTIONS: Array[int] = [30, 60, 120, 0]
const FPS_LABELS: Array[String] = ["30", "60", "120", "不限"]
const DEFAULT_FPS_INDEX: int = 3

## 加速模式下的时长倍率。延时和动画时长都乘它。
const FAST_SCALE: float = 0.5
## 敌人回合里每个敌人之间的基准停顿（秒）。
const ENEMY_STEP_DELAY: float = 0.5

## 「字体更大」的倍率。界面上写死的字号统一乘它。
const FONT_SCALE_BIG: float = 1.25

## 可以改键的动作。键是内部动作名，值是表上显示的中文名。
## 想知道某一行有没有东西响应，看这张表就够了。
## 表里混着三种来源：引擎自带的（ui_cancel / ui_up / ui_down / ui_left / ui_right）、
## project.godot 里定义的本项目动作（其余那些）、以及它们被玩家改绑后的样子——对这张表来说没区别。
const BINDABLE_ACTIONS: Dictionary = {
	"ui_cancel": "取消/退出",
	"confirm_play": "确认选牌",
	"view_deck": "查看牌组",
	"draw_pile": "抽牌堆",
	"discard_pile": "弃牌堆",
	"exhaust_pile": "消耗堆",
	"end_turn": "结束回合",
	"view_status": "察看状态",
	"map": "地图",
	"view_history": "本场战报",
	"ui_up": "上",
	"ui_down": "下",
	"ui_left": "左",
	"ui_right": "右",
}

## 四个方向键显示成中文。表是全中文的，就这四行冒「Up」「Left」很扎眼；
## 玩家把它们改绑成别的键之后不在这张表里，照常显示那个键自己的名字。
const ARROW_KEY_LABELS: Dictionary = {
	KEY_UP: "上",
	KEY_DOWN: "下",
	KEY_LEFT: "左",
	KEY_RIGHT: "右",
}

var resolution_index: int = DEFAULT_RESOLUTION_INDEX
var max_fps_index: int = DEFAULT_FPS_INDEX
var fullscreen: bool = false
var borderless: bool = false
var vsync: bool = true

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var mute_on_focus_lost: bool = true

## 背景音效：战斗里低沉的嗡鸣、地图上安静的氛围声。管的是环境音那一层，BGM 不受它影响。
var ambient: bool = true

var screen_shake: bool = true
var particles: bool = true
var fast_mode: bool = false

## 战斗动态效果：立绘的待机浮动/呼吸、受击闪白+后仰、出手前冲。一条管全部，
## 嫌画面晃的玩家一下就能全关掉（和「屏幕震动」「关闭粒子」一个档次）。
var battle_motion: bool = true

## 挨打时头顶飘的数字：金色是实际扣的血，蓝色是被格挡吃掉的那部分。两个开关各管一种。
var damage_number_gold: bool = true
var damage_number_blue: bool = true

## 手牌角上标出 1~9/0，按数字键直接打出。
var show_play_keys: bool = true

## 只选择一张牌时不需要确认：开着就点一下直接出牌，关掉要先选中、再按「确认选牌」才打出去。
## 默认开着＝和以前一样点一下即出，免得加了这个开关反而把惯用手感改掉。
var skip_confirm_single: bool = true

## 长按确认：结束回合、覆盖存档这种「点错就回不去」的按钮，改成按住才算数。
var hold_to_confirm: bool = false

## 字体更大：界面上写死的字号统一乘 FONT_SCALE_BIG。
var font_larger: bool = false

## 窗口是不是正处于失焦状态。和音量分开记，免得「音量拉到 0」和「切到后台」互相把静音状态覆盖掉。
var _focus_muted: bool = false


func _ready() -> void:
	load_settings()
	apply_all()


func _notification(what: int) -> void:
	# 切到后台时静音。这是引擎的窗口焦点通知，全树都会收到。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_muted = true
		_refresh_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_muted = false
		_refresh_audio()


# --- 对外读数 ---

func resolution() -> Vector2i:
	return RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]


func resolution_label() -> String:
	return RESOLUTION_LABELS[clampi(resolution_index, 0, RESOLUTION_LABELS.size() - 1)]


func max_fps() -> int:
	return FPS_OPTIONS[clampi(max_fps_index, 0, FPS_OPTIONS.size() - 1)]


## 动画与停顿的时长倍率。加速模式下会变小。
func anim_scale() -> float:
	return FAST_SCALE if fast_mode else 1.0


## 界面上写死的字号统一乘它。谁来乘是 UiFontScale 的事，这里只出数。
func font_scale() -> float:
	return FONT_SCALE_BIG if font_larger else 1.0


func enemy_step_delay() -> float:
	return ENEMY_STEP_DELAY * anim_scale()


# --- 应用 ---

func apply_all() -> void:
	apply_display()
	_refresh_audio()


func apply_display() -> void:
	# 独占全屏优先，其次无边框，都不是就是普通窗口。两者互斥，界面那边保证不会同时勾上。
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	elif borderless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# 全屏时窗口尺寸由显示器说了算，分辨率只在窗口模式下管用。
		DisplayServer.window_set_size(resolution())
		_center_window()
	Engine.max_fps = max_fps()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var window := DisplayServer.window_get_size()
	DisplayServer.window_set_position(usable.position + (usable.size - window) / 2)


## 把「音量」和「失焦静音」合成一个静音状态再写到总线上。
## 分成两步是因为两者都能让总线静音，谁最后写谁说了算会把对方抹掉。
func _refresh_audio() -> void:
	_set_bus_level("Master", master_volume)
	_set_bus_level(SFX_BUS, sfx_volume)
	_set_bus_level(MUSIC_BUS, music_volume)


func _set_bus_level(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	# 拉到 0 就直接静音：linear_to_db(0) 是负无穷，写进去反而不好收场。
	AudioServer.set_bus_mute(idx, _focus_muted or linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_refresh_audio()
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_refresh_audio()
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_refresh_audio()
	save_settings()


## 环境音那一层播不播由 MusicManager 说了算，它每帧会看这个值，这里只管存。
func set_ambient(on: bool) -> void:
	ambient = on
	save_settings()


func set_mute_on_focus_lost(on: bool) -> void:
	mute_on_focus_lost = on
	if not on:
		_focus_muted = false
	_refresh_audio()
	save_settings()


# --- 按键 ---

func binding_event(action: String) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event
	return null


## 表上显示用的键名。没绑定就显示「未绑定」（键被别的行抢走时会出现）。
func binding_text(action: String) -> String:
	var event := binding_event(action)
	if event == null:
		return "未绑定"
	var key := event as InputEventKey
	var code := _effective_keycode(key)
	if ARROW_KEY_LABELS.has(code):
		var arrow: String = ARROW_KEY_LABELS[code]
		return arrow
	# 引擎自带的 ui_cancel 只记 keycode、没有 physical_keycode，反过来新绑的只记 physical。
	# 两边都看一眼，否则 ESC 那行会显示成「(unset)」。
	if key.physical_keycode != 0:
		return key.as_text_physical_keycode()
	return key.as_text_keycode()


## 从按下的键造一个干净的绑定事件。
## 一律记「物理键」：物理键跟键盘布局无关，玩家换成别的布局键位不会跟着跑。
## project.godot 里那六个默认键也是按物理键写的，两边保持一致。
static func make_binding_event(key_event: InputEventKey) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key_event.physical_keycode if key_event.physical_keycode != 0 \
			else key_event.keycode
	event.device = -1
	return event


## 把某个动作改绑到刚按下的键。同一个键不许占两行：原本占着它的那行直接清空，
## 否则按一下会同时触发两件事，而且玩家没法从表上看出来。
func rebind(action: String, event: InputEvent) -> void:
	if not BINDABLE_ACTIONS.has(action):
		return
	var binding: InputEvent = event
	if event is InputEventKey:
		binding = make_binding_event(event as InputEventKey)
	for other: Variant in BINDABLE_ACTIONS.keys():
		var other_action: String = other
		if other_action != action and _has_binding(other_action, binding):
			InputMap.action_erase_events(other_action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, binding)
	save_settings()


## 还原成出厂键位。project.godot 的 [input] 段就是出厂值，引擎自带这个还原入口。
func reset_bindings() -> void:
	InputMap.load_from_project_settings()
	save_settings()


func _has_binding(action: String, event: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if _same_key(existing, event):
			return true
	return false


## 比的是「实际按下的是哪个键」：两边都先归一到一个有效键码再比。
## 不归一的话，引擎自带 ESC（只有 keycode）和新绑的 ESC（只有 physical_keycode）会被判成不同的键，
## 于是同一个键悄悄占了两行。
func _same_key(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var code_a := _effective_keycode(a as InputEventKey)
		var code_b := _effective_keycode(b as InputEventKey)
		return code_a != 0 and code_a == code_b
	return a.is_match(b)


func _effective_keycode(key: InputEventKey) -> int:
	return key.physical_keycode if key.physical_keycode != 0 else key.keycode


# --- 落盘 ---

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "max_fps_index", max_fps_index)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "borderless", borderless)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "mute_on_focus_lost", mute_on_focus_lost)
	cfg.set_value("audio", "ambient", ambient)
	cfg.set_value("gameplay", "screen_shake", screen_shake)
	cfg.set_value("gameplay", "particles", particles)
	cfg.set_value("gameplay", "battle_motion", battle_motion)
	cfg.set_value("gameplay", "fast_mode", fast_mode)
	cfg.set_value("gameplay", "damage_number_gold", damage_number_gold)
	cfg.set_value("gameplay", "damage_number_blue", damage_number_blue)
	cfg.set_value("gameplay", "show_play_keys", show_play_keys)
	cfg.set_value("gameplay", "skip_confirm_single", skip_confirm_single)
	cfg.set_value("misc", "hold_to_confirm", hold_to_confirm)
	cfg.set_value("misc", "font_larger", font_larger)
	# 键位直接存输入事件本身，ConfigFile 能原样存取引擎对象，不用自己拼字符串。
	# 没绑定的行故意不写：读的时候「文件里有 keys 段却没有这一行」就等于「这行是空的」。
	for action: Variant in BINDABLE_ACTIONS.keys():
		var event := binding_event(String(action))
		if event != null:
			cfg.set_value("keys", String(action), event)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return        # 头一次跑还没有文件，全用默认值
	resolution_index = int(cfg.get_value("display", "resolution_index", resolution_index))
	max_fps_index = int(cfg.get_value("display", "max_fps_index", max_fps_index))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	borderless = bool(cfg.get_value("display", "borderless", borderless))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music_volume", music_volume))
	mute_on_focus_lost = bool(cfg.get_value("audio", "mute_on_focus_lost", mute_on_focus_lost))
	ambient = bool(cfg.get_value("audio", "ambient", ambient))
	screen_shake = bool(cfg.get_value("gameplay", "screen_shake", screen_shake))
	particles = bool(cfg.get_value("gameplay", "particles", particles))
	battle_motion = bool(cfg.get_value("gameplay", "battle_motion", battle_motion))
	fast_mode = bool(cfg.get_value("gameplay", "fast_mode", fast_mode))
	damage_number_gold = bool(cfg.get_value("gameplay", "damage_number_gold", damage_number_gold))
	damage_number_blue = bool(cfg.get_value("gameplay", "damage_number_blue", damage_number_blue))
	show_play_keys = bool(cfg.get_value("gameplay", "show_play_keys", show_play_keys))
	skip_confirm_single = bool(cfg.get_value("gameplay", "skip_confirm_single", skip_confirm_single))
	hold_to_confirm = bool(cfg.get_value("misc", "hold_to_confirm", hold_to_confirm))
	font_larger = bool(cfg.get_value("misc", "font_larger", font_larger))
	if not cfg.has_section("keys"):
		return        # 老文件没有键位段，按键保持 project.godot 的出厂值
	for action: Variant in BINDABLE_ACTIONS.keys():
		var action_name: String = action
		if cfg.has_section_key("keys", action_name):
			var event: Variant = cfg.get_value("keys", action_name, null)
			if event is InputEvent:
				InputMap.action_erase_events(action_name)
				InputMap.action_add_event(action_name, event)
		else:
			# 存盘时这一行就是空的（键被别的行抢走了），照样还原成空。
			InputMap.action_erase_events(action_name)
