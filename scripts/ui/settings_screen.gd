class_name SettingsScreen
extends ColorRect

## 设定页。参考杀戮尖塔：顶部两个页签（游戏设置 / 操作设置），下面一个可滚动的框。
## 设定入口那两张卡片进的是**同一个页面**，只是默认停在不同页签。
##
## 这里摆的每一项背后都真有东西可控制——参考界面里缺的功能是**把功能补出来**，
## 不是把开关砍掉。目前只剩两样没摆：触屏模式（本机没有触摸屏）和上传游戏数据
## （单机项目没有服务器可传）。
##
## 游戏设置页照参考排成四块：上排「画面 | 声音」，下排「偏好 | 杂项」。

const TAB_GAME := 0
const TAB_CONTROLS := 1

const HEADING_COLOR := Color(0.95, 0.82, 0.45)
const MUTED := Color(0.62, 0.60, 0.70)
const LABEL_WIDTH := 260.0
const KEY_BUTTON_WIDTH := 220.0

## 关掉自己时说一声。就地盖在战斗 / 地图上时，暂停是开着设置的这一方负责的，
## 得靠这个信号把暂停还原回去。
signal closed

var _tab: int = TAB_GAME
var _body: VBoxContainer
var _tab_buttons: Array[Button] = []
var _fullscreen_check: CheckBox
var _borderless_check: CheckBox
var _key_buttons: Dictionary = {}

## 正在等玩家按键的那一行（空串表示没在等）。改绑一次只允许一行。
var _listening_action: String = ""
var _listen_button: Button = null


func setup(tab: int) -> void:
	_tab = tab


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0.06, 0.06, 0.12, 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_add_background()
	_build()


## 设定页是从主菜单或战斗里就地盖上来的一层，底图沿用主菜单那张水墨。
## 面板本身是 0.98 的不透明深底，字不会被底图干扰；压暗后只在中缝和四周露出纹理。
func _add_background() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Background"
	backdrop.color = color
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	UIBackground.apply(self, "main_menu", 0.5)


## 改绑时要用 _input 抢在界面控件前面拿到按键。
##
## ESC 有两条路，都得在这里（输入链第一站，一定跑在全局那个 ESC 前面）吃掉事件：
## 改绑中 → 取消这次改绑，页面留着；没在改绑 → 关掉自己。
## 不吃的话，就地盖在战斗 / 地图上时这一下会漏给全局，变成「关掉设置的同时顺手弹出暂停菜单」。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _listening_action.is_empty():
			_on_back()
		else:
			_stop_listening()
		return
	if _listening_action.is_empty() or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_ESCAPE:
		# ESC 留着当「取消这次改绑」用，所以它不能被绑到任何一行上。
		_stop_listening()
		return
	SettingsManager.rebind(_listening_action, key)
	_stop_listening()
	# 绑到别人在用的键会把那一行清空，所以整张表都得重刷，不能只刷这一行。
	_refresh_key_buttons()


# --- 骨架 ---

func _build() -> void:
	add_child(_make_title("设定"))

	var tabs := HBoxContainer.new()
	tabs.anchor_left = 0.5
	tabs.anchor_top = 0.0
	tabs.anchor_right = 0.5
	tabs.anchor_bottom = 0.0
	# 匾额下沿压在 110 左右，页签得让开它，别贴着匾额底边。
	tabs.offset_top = 126.0
	tabs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tabs.add_theme_constant_override("separation", 12)
	add_child(tabs)
	_tab_buttons = [
		_add_tab_button(tabs, "游戏设置", TAB_GAME),
		_add_tab_button(tabs, "操作设置", TAB_CONTROLS),
	]

	var scroll := ScrollContainer.new()
	scroll.anchors_preset = PRESET_FULL_RECT
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 160.0
	scroll.offset_top = 184.0
	scroll.offset_right = -160.0
	scroll.offset_bottom = -92.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	scroll.add_child(_body)

	add_child(_make_back_button())
	add_child(_make_quit_button())

	_rebuild_body()


func _rebuild_body() -> void:
	# 先 remove 再 queue_free：queue_free 是延迟的，只 queue 的话这一帧新旧两批会同时挂着。
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_listening_action = ""
	_listen_button = null
	_key_buttons.clear()
	if _tab == TAB_GAME:
		_build_game_tab()
	else:
		_build_controls_tab()
	_refresh_tabs()


func _on_tab_pressed(tab: int) -> void:
	if tab == _tab:
		return
	_tab = tab
	_rebuild_body()


func _refresh_tabs() -> void:
	for button in _tab_buttons:
		var active: bool = int(button.get_meta("tab")) == _tab
		button.add_theme_color_override("font_color", HEADING_COLOR if active else MUTED)


func _add_tab_button(parent: HBoxContainer, text: String, tab: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 40)
	button.add_theme_font_size_override("font_size", 19)
	button.set_meta("tab", tab)
	button.pressed.connect(_on_tab_pressed.bind(tab))
	parent.add_child(button)
	return button


# --- 游戏设置页 ---

func _build_game_tab() -> void:
	var top := _make_row_box()
	var bottom := _make_row_box()

	var display := _add_panel(top, "画面")
	_add_dropdown(display, "分辨率", SettingsManager.RESOLUTION_LABELS,
		SettingsManager.resolution_index, _on_resolution_changed)
	_add_dropdown(display, "最大帧数", SettingsManager.FPS_LABELS,
		SettingsManager.max_fps_index, _on_max_fps_changed)
	_fullscreen_check = _add_check(display, "全屏模式", SettingsManager.fullscreen,
		_on_fullscreen_toggled)
	_borderless_check = _add_check(display, "无边框全屏（推荐）", SettingsManager.borderless,
		_on_borderless_toggled)
	# 参考界面里这两个是并排一行。
	_add_check_pair(display,
		"屏幕震动", SettingsManager.screen_shake, _on_screen_shake_toggled,
		"垂直同步", SettingsManager.vsync, _on_vsync_toggled)
	display.add_child(_hint("分辨率只在窗口模式下管用：全屏时窗口尺寸由显示器说了算。"))
	if Engine.is_embedded_in_editor():
		display.add_child(_hint("当前是编辑器内嵌运行：窗口由编辑器托管，改分辨率和全屏都不会生效。在 Game 栏右上角菜单里关掉「嵌入游戏（Embed Game on Next Play）」，或导出成 exe 再试。"))

	var audio := _add_panel(top, "声音")
	_add_slider(audio, "主音量", SettingsManager.master_volume,
		Callable(SettingsManager, "set_master_volume"))
	_add_slider(audio, "音乐音量", SettingsManager.music_volume,
		Callable(SettingsManager, "set_music_volume"))
	_add_slider(audio, "音效音量", SettingsManager.sfx_volume,
		Callable(SettingsManager, "set_sfx_volume"))
	_add_check(audio, "在背景运行时静音", SettingsManager.mute_on_focus_lost,
		_on_focus_mute_toggled)
	_add_check(audio, "背景音效", SettingsManager.ambient, _on_ambient_toggled)
	audio.add_child(_hint("背景音效：战斗里低沉的嗡鸣、地图上安静的氛围声。"))

	# 偏好这块照参考的顺序排：伤害数字那两条在最前。
	var preference := _add_panel(bottom, "偏好")
	_add_check(preference, "用金色数字显示伤害的总和", SettingsManager.damage_number_gold,
		_on_damage_number_gold_toggled)
	_add_check(preference, "用蓝色数字显示被格挡伤害的总和", SettingsManager.damage_number_blue,
		_on_damage_number_blue_toggled)
	# 勾选框写的是「关闭粒子效果」，存的是「粒子开着没有」，这里要反一下。
	_add_check(preference, "关闭粒子效果", not SettingsManager.particles, _on_particles_toggled)
	_add_check(preference, "加速模式", SettingsManager.fast_mode, _on_fast_mode_toggled)
	_add_check(preference, "战斗动态效果", SettingsManager.battle_motion,
		_on_battle_motion_toggled)
	_add_check(preference, "显示快速选牌按键", SettingsManager.show_play_keys,
		_on_show_play_keys_toggled)
	_add_check(preference, "在只选择一张牌时，不需要确认", SettingsManager.skip_confirm_single,
		_on_skip_confirm_toggled)
	preference.add_child(_hint("加速模式会把翻牌动画和敌人出手之间的停顿都缩短一半。"))
	preference.add_child(_hint("战斗动态效果：立绘的待机浮动、受击后仰和出手动作。关掉就全是静止的。"))
	preference.add_child(_hint("显示快速选牌按键：手牌右上角标出 1~9/0，按数字键直接打出。"))
	preference.add_child(_hint("「不需要确认」：点一下手牌就出手；取消勾选则先选中，再按「确认选牌」才打出去。"))

	var misc := _add_panel(bottom, "杂项")
	_add_check(misc, "长按确认", SettingsManager.hold_to_confirm, _on_hold_to_confirm_toggled)
	_add_check(misc, "字体更大", SettingsManager.font_larger, _on_font_larger_toggled)
	misc.add_child(_hint("长按确认：结束回合、覆盖存档这类按钮要按住不放才生效。"))
	misc.add_child(_hint("字体更大：界面上写死的字号统一放大。"))


func _on_resolution_changed(index: int) -> void:
	SettingsManager.resolution_index = index
	_apply_display_settings()


func _on_max_fps_changed(index: int) -> void:
	SettingsManager.max_fps_index = index
	_apply_display_settings()


func _on_vsync_toggled(on: bool) -> void:
	SettingsManager.vsync = on
	_apply_display_settings()


func _on_screen_shake_toggled(on: bool) -> void:
	SettingsManager.screen_shake = on
	SettingsManager.save_settings()


## 全屏和无边框是两种互斥的全屏方式，勾上一个就把另一个取消掉。
func _on_fullscreen_toggled(on: bool) -> void:
	SettingsManager.fullscreen = on
	if on:
		SettingsManager.borderless = false
		# 用 no_signal 版本，免得反过来又触发一次那个勾选框的回调。
		_borderless_check.set_pressed_no_signal(false)
	_apply_display_settings()


func _on_borderless_toggled(on: bool) -> void:
	SettingsManager.borderless = on
	if on:
		SettingsManager.fullscreen = false
		_fullscreen_check.set_pressed_no_signal(false)
	_apply_display_settings()


func _apply_display_settings() -> void:
	SettingsManager.apply_display()
	SettingsManager.save_settings()


func _on_focus_mute_toggled(on: bool) -> void:
	SettingsManager.set_mute_on_focus_lost(on)


## 环境音那一层是 MusicManager 在放，改完让它立刻重来一遍，别等下一帧。
func _on_ambient_toggled(on: bool) -> void:
	SettingsManager.set_ambient(on)
	MusicManager.refresh()


func _on_particles_toggled(off: bool) -> void:
	SettingsManager.particles = not off
	SettingsManager.save_settings()


func _on_fast_mode_toggled(on: bool) -> void:
	SettingsManager.fast_mode = on
	SettingsManager.save_settings()


## 战斗动态效果：改完当场生效。设定页是从战斗里按 ESC 开出来的，场上的立绘还在，
## 拿当前战斗给它重新起/停一次待机就行（没在战斗里 get_active_battle 返回 null）。
func _on_battle_motion_toggled(on: bool) -> void:
	SettingsManager.battle_motion = on
	SettingsManager.save_settings()
	var bm := GameManager.get_active_battle()
	if bm != null:
		bm.refresh_unit_motion()


func _on_damage_number_gold_toggled(on: bool) -> void:
	SettingsManager.damage_number_gold = on
	SettingsManager.save_settings()


func _on_damage_number_blue_toggled(on: bool) -> void:
	SettingsManager.damage_number_blue = on
	SettingsManager.save_settings()


## 快速选牌角标：同样当场生效。角标本是靠能量变化那一路刷的，改设定不动能量，
## 不主动刷一次就得等下一回合才看得见——玩家报的「开或关不会立即显现」就是这个。
func _on_show_play_keys_toggled(on: bool) -> void:
	SettingsManager.show_play_keys = on
	SettingsManager.save_settings()
	var bm := GameManager.get_active_battle()
	if bm != null:
		bm.refresh_play_keys()


func _on_skip_confirm_toggled(on: bool) -> void:
	SettingsManager.skip_confirm_single = on
	SettingsManager.save_settings()


func _on_hold_to_confirm_toggled(on: bool) -> void:
	SettingsManager.hold_to_confirm = on
	SettingsManager.save_settings()


func _on_font_larger_toggled(on: bool) -> void:
	SettingsManager.font_larger = on
	SettingsManager.save_settings()
	# 已经摆在屏幕上的界面也得跟着变，不能只管以后新加进来的控件。
	UiFontScale.refresh()


# --- 操作设置页 ---

func _build_controls_tab() -> void:
	var panel := _add_panel(_body, "指令与按键")
	panel.add_child(_table_header())

	for action: Variant in SettingsManager.BINDABLE_ACTIONS.keys():
		var action_name: String = action
		panel.add_child(_table_row(action_name))

	panel.add_child(_hint("点某一行的按键就能改绑，接着按下想用的键即可；改绑时按 ESC 取消。"))
	panel.add_child(_hint("同一个键只能管一行：绑到别人正在用的键，那一行会变成「未绑定」。"))

	var reset := Button.new()
	reset.text = "重置为默认"
	# 不加这一句，VBox 会把它拉成整块面板那么宽。
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.custom_minimum_size = Vector2(160, 38)
	reset.add_theme_font_size_override("font_size", 16)
	reset.pressed.connect(_on_reset_bindings)
	panel.add_child(reset)


func _table_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_cell_label("指令", true))
	row.add_child(_cell_label("键盘", true))
	return row


func _table_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_cell_label(String(SettingsManager.BINDABLE_ACTIONS[action]), false))

	var key_button := Button.new()
	key_button.custom_minimum_size = Vector2(KEY_BUTTON_WIDTH, 34)
	key_button.add_theme_font_size_override("font_size", 16)
	key_button.text = SettingsManager.binding_text(action)
	key_button.pressed.connect(_on_key_button_pressed.bind(action, key_button))
	row.add_child(key_button)
	_key_buttons[action] = key_button

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	return row


func _cell_label(text: String, is_header: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH if not is_header else LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	if is_header:
		label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _on_key_button_pressed(action: String, button: Button) -> void:
	# 再点一次同一行就是取消。
	if _listening_action == action:
		_stop_listening()
		return
	_stop_listening()
	_listening_action = action
	_listen_button = button
	button.text = "按任意键…"


func _stop_listening() -> void:
	if _listen_button != null and is_instance_valid(_listen_button) and not _listening_action.is_empty():
		_listen_button.text = SettingsManager.binding_text(_listening_action)
	_listening_action = ""
	_listen_button = null


func _refresh_key_buttons() -> void:
	for action: Variant in _key_buttons.keys():
		var action_name: String = action
		var button: Button = _key_buttons[action_name]
		if is_instance_valid(button):
			button.text = SettingsManager.binding_text(action_name)


func _on_reset_bindings() -> void:
	SettingsManager.reset_bindings()
	_stop_listening()
	_refresh_key_buttons()


# --- 排版零件 ---

func _make_row_box() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_body.add_child(row)
	return row


## 建一块面板，返回它的内容区（VBox），调用方接着往里面加行。
func _add_panel(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_box())
	parent.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	body.add_child(heading)
	return body


## 「名字……控件」这一行的前半截，返回 HBox 供调用方把控件接在后面。
func _add_row(body: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	return row


func _add_dropdown(body: VBoxContainer, label_text: String, options: Array[String],
		selected: int, on_change: Callable) -> OptionButton:
	var row := _add_row(body, label_text)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(200, 32)
	for option in options:
		picker.add_item(option)
	picker.selected = clampi(selected, 0, options.size() - 1)
	picker.item_selected.connect(on_change)
	row.add_child(picker)
	return picker


func _add_check(body: VBoxContainer, label_text: String, pressed: bool,
		on_change: Callable) -> CheckBox:
	return _make_check(body, label_text, pressed, on_change)


## 参考界面里「屏幕震动」和「垂直同步」是并排一行。返回按顺序排的那两个框。
func _add_check_pair(body: VBoxContainer,
		first_text: String, first_on: bool, first_handler: Callable,
		second_text: String, second_on: bool, second_handler: Callable) -> Array[CheckBox]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	body.add_child(row)
	var boxes: Array[CheckBox] = []
	boxes.append(_make_check(row, first_text, first_on, first_handler))
	boxes.append(_make_check(row, second_text, second_on, second_handler))
	return boxes


## 勾选框的统一造法。父节点收 Control 而不是 VBox：并排一行时父节点是 HBox。
func _make_check(parent: Control, label_text: String, pressed: bool,
		on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = label_text
	box.button_pressed = pressed
	box.add_theme_font_size_override("font_size", 16)
	# 引擎默认的两个状态图标是近黑的，压在深底上看不见，换成自己画的。
	CheckIcon.apply(box)
	box.toggled.connect(on_change)
	parent.add_child(box)
	return box


func _add_slider(body: VBoxContainer, label_text: String, value: float, handler: Callable) -> void:
	var row := _add_row(body, label_text)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := Label.new()
	readout.text = "%d%%" % roundi(value * 100.0)
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", 16)
	row.add_child(readout)

	slider.value_changed.connect(_on_slider_changed.bind(readout, handler))


func _on_slider_changed(value: float, readout: Label, handler: Callable) -> void:
	readout.text = "%d%%" % roundi(value * 100.0)
	handler.call(value)


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _make_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -300.0
	label.offset_top = 40.0
	label.offset_right = 300.0
	label.offset_bottom = 92.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	UiTitlePlaque.apply(label, 44)
	return label


func _make_back_button() -> Button:
	var button := Button.new()
	button.text = "返回"
	button.anchor_left = 0.0
	button.anchor_top = 1.0
	button.anchor_right = 0.0
	button.anchor_bottom = 1.0
	button.offset_left = 110.0
	button.offset_top = -80.0
	button.offset_right = 250.0
	button.offset_bottom = -32.0
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_on_back)
	return button


func _make_quit_button() -> Button:
	var button := Button.new()
	button.text = "退出游戏"
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = -250.0
	button.offset_top = -80.0
	button.offset_right = -110.0
	button.offset_bottom = -32.0
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_on_quit)
	return button


func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.10, 0.16, 0.98)
	box.border_color = Color(0.30, 0.28, 0.40)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	return box


func _on_back() -> void:
	closed.emit()
	queue_free()


func _on_quit() -> void:
	get_tree().quit()
