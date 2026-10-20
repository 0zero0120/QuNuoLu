class_name SaveSlotScreen
extends Control

var mode: String = "load"
var _slots_box: VBoxContainer
var _confirm_box: Control = null

func setup(m: String) -> void:
	mode = m

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0

	var dim := ColorRect.new()
	dim.anchors_preset = PRESET_FULL_RECT
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.anchors_preset = PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_top = -240.0
	panel.offset_right = 320.0
	panel.offset_bottom = 240.0
	panel.add_theme_stylebox_override("panel", _solid_box())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = PRESET_FULL_RECT
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 24.0
	vbox.offset_top = 20.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择存档" if mode == "load" else "选择新游戏槽位"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_slots_box)
	_refresh_slots()

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(0, 44)
	back_button.pressed.connect(_close)
	vbox.add_child(back_button)

func _refresh_slots() -> void:
	for child in _slots_box.get_children():
		child.queue_free()
	for slot in range(GameManager.SAVE_SLOT_COUNT):
		_slots_box.add_child(_make_slot_row(slot))

func _make_slot_row(slot: int) -> Control:
	var summary := GameManager.get_save_summary(slot)
	var filled := not summary.is_empty()

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 60)
	row.add_theme_stylebox_override("panel", _solid_box())
	var hbox := HBoxContainer.new()
	hbox.anchors_preset = PRESET_FULL_RECT
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 12.0
	hbox.offset_top = 6.0
	hbox.offset_right = -12.0
	hbox.offset_bottom = -6.0
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = "槽位 %d" % (slot + 1)
	name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(name_label)

	var detail_label := Label.new()
	detail_label.add_theme_font_size_override("font_size", 13)
	if filled:
		detail_label.text = "%s · %s · 第 %d 层 · HP %d/%d · 金币 %d" % [
			summary.get("character_name", "?"),
			AscensionText.label(int(summary.get("ascension", 1))),
			summary.get("floor", 0),
			summary.get("current_hp", 0),
			summary.get("max_hp", 0),
			summary.get("gold", 0),
		]
	else:
		detail_label.text = "空槽位"
		detail_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	info.add_child(detail_label)

	if mode == "load":
		if filled:
			var load_btn := Button.new()
			load_btn.text = "加载"
			load_btn.custom_minimum_size = Vector2(80, 40)
			load_btn.pressed.connect(func(): _on_load(slot))
			hbox.add_child(load_btn)
	else:
		var start_btn := Button.new()
		start_btn.text = "覆盖" if filled else "新游戏"
		start_btn.custom_minimum_size = Vector2(100, 40)
		start_btn.pressed.connect(func(): _on_new(slot))
		hbox.add_child(start_btn)

	# 「删除」两个入口都要有：只挂在「继续游戏」下的话，从「开始游戏」进来的玩家
	# 看着一个不想要的旧档，既开不了新局也删不掉它。
	if filled:
		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(80, 40)
		del_btn.pressed.connect(func(): _on_delete(slot))
		hbox.add_child(del_btn)

	return row

func _on_load(slot: int) -> void:
	if not GameManager.load_run(slot):
		_refresh_slots()
		return
	# 存档里带着「上一次停在哪个界面」：战斗停在开局，商店/休息/事件/奖励停在原地。
	# 直接回那个界面，而不是把玩家丢回地图——地图上那个节点已经 visited，回不去了。
	GameManager.change_screen(GameManager.resume_screen)

func _on_delete(slot: int) -> void:
	# 删除是不可逆的：先问一句，手滑一次原来那一局就没了。和覆盖确认同一套观感。
	if is_instance_valid(_confirm_box):
		_confirm_box.queue_free()
	var summary := GameManager.get_save_summary(slot)
	var text := "槽位 %d 已有存档：%s · 第 %d 层 · HP %d/%d。\n删除后这一局无法找回。" % [
		slot + 1,
		summary.get("character_name", "?"),
		summary.get("floor", 0),
		summary.get("current_hp", 0),
		summary.get("max_hp", 0),
	]
	_confirm_box = _build_confirm(text, "删除", func(): _do_delete(slot))
	add_child(_confirm_box)

func _do_delete(slot: int) -> void:
	GameManager.delete_run(slot)
	_refresh_slots()

func _on_new(slot: int) -> void:
	# 空槽位直接进角色选择；已有存档的先问一句——手滑一次原来那一局就没了。
	if not GameManager.has_save(slot):
		_start_new_at(slot)
		return
	_confirm_overwrite(slot)

## 覆盖确认。样式跟着本页的 `_build_ui()` 走（暗底 + 面板 + 两个按钮），
## 不另造一套弹窗观感，也不弹引擎默认皮肤的对话框。
func _confirm_overwrite(slot: int) -> void:
	if is_instance_valid(_confirm_box):
		_confirm_box.queue_free()
	var summary := GameManager.get_save_summary(slot)
	var text := "槽位 %d 已有存档：%s · 第 %d 层 · HP %d/%d。\n覆盖后这一局不会计入战绩，也无法找回。" % [
		slot + 1,
		summary.get("character_name", "?"),
		summary.get("floor", 0),
		summary.get("current_hp", 0),
		summary.get("max_hp", 0),
	]
	_confirm_box = _build_confirm(text, "覆盖", func(): _start_new_at(slot))
	add_child(_confirm_box)

func _start_new_at(slot: int) -> void:
	GameManager.pending_new_slot = slot
	GameManager.change_screen(GameManager.GameScreen.CHARACTER_SELECT)

func _build_confirm(text: String, ok_text: String, on_ok: Callable) -> Control:
	var root := Control.new()
	root.anchors_preset = PRESET_FULL_RECT
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0

	var dim := ColorRect.new()
	dim.anchors_preset = PRESET_FULL_RECT
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := Panel.new()
	panel.anchors_preset = PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_top = -110.0
	panel.offset_right = 280.0
	panel.offset_bottom = 110.0
	panel.add_theme_stylebox_override("panel", _solid_box())
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = PRESET_FULL_RECT
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 24.0
	vbox.offset_top = 20.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)

	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(120, 40)
	cancel_button.pressed.connect(func(): root.queue_free())
	row.add_child(cancel_button)

	var ok_button := Button.new()
	ok_button.text = ok_text
	ok_button.custom_minimum_size = Vector2(120, 40)
	# 开了「长按确认」就得按住一会儿才生效——覆盖存档点错了回不去。
	HoldToConfirm.attach(ok_button, func():
		root.queue_free()
		on_ok.call(), SettingsManager.hold_to_confirm)
	row.add_child(ok_button)

	return root

## 引擎默认的 Panel 样式是半透明的（bg alpha 0.6）：面板叠面板时下面那一层的字会透上来，
## 覆盖确认框压在存档页上时尤其明显。本页所有面板统一用这只不透明的深底。
func _solid_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.09, 0.13)
	box.border_color = Color(0.30, 0.30, 0.40)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box

func _close() -> void:
	queue_free()
