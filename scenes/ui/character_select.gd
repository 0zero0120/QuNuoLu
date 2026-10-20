class_name CharacterSelect
extends Control

const DETAIL_SCRIPT := "res://scripts/ui/character_detail.gd"
## 版面：立绘占上面一大块，底下一行写名字和血量。给立绘留的是竖幅，别按方形给。
## 240x360 是 1080p 下四张并排仍留得开边、立绘又够看的档位；立绘源是 2:3，槽再方就全是空边。
const ICON_SIZE := Vector2(240, 360)
const PORTRAIT_MARGIN := 10.0
const CAPTION_HEIGHT := 78.0
const TITLE_FONT: FontFile = preload("res://assets/fonts/MaShanZheng-Regular.ttf")


func _ready() -> void:
	UIBackground.apply(self, "character_select")
	_decorate_title()
	_style_back_button()
	$BackButton.pressed.connect(_on_back)
	_populate()


func _populate() -> void:
	var row := $CharRow
	for character: PlayerData in DataManager.characters_in_order():
		row.add_child(_make_icon(character))


# --- 标题与返回 ---

## 主菜单那面匾额复用过来，副标题类的界面才不至于只剩一行白字。
## 图读不到就什么都不加，标题照旧显示（同主菜单的口径）。
func _decorate_title() -> void:
	var title := $TitleLabel as Label
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.93, 0.90, 0.82, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 0.9))
	title.add_theme_constant_override("outline_size", 8)

	var plaque := UIBackground.load_or_null("title_plaque")
	if plaque == null:
		return
	var image := TextureRect.new()
	image.name = "TitlePlaque"
	image.texture = plaque
	image.show_behind_parent = true
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = -110.0
	image.offset_top = -55.0
	image.offset_right = 110.0
	image.offset_bottom = 55.0
	title.add_child(image)

	var subtitle := Label.new()
	subtitle.text = "不同出身，起手牌与气血各不相同"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70, 1.0))
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	subtitle.add_theme_constant_override("outline_size", 4)
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 1.0
	subtitle.anchor_bottom = 1.0
	subtitle.offset_top = 6.0
	subtitle.offset_bottom = 30.0
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(subtitle)


func _style_back_button() -> void:
	var button := $BackButton as Button
	button.add_theme_stylebox_override("normal", _button_style(Color(0.05, 0.05, 0.08, 0.72),
		Color(0.55, 0.50, 0.35, 0.55)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.12, 0.18, 0.88),
		Color(0.85, 0.70, 0.40, 0.95)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.14, 0.12, 0.95),
		Color(0.95, 0.80, 0.50, 1.0)))
	button.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


# --- 角色卡 ---

func _make_icon(character: PlayerData) -> Button:
	var button := Button.new()
	# 按角色 id 命名，核验脚本要按名字点某一张卡（库的遍历次序不保证）。
	button.name = character.character_id
	button.custom_minimum_size = ICON_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _card_style(character, 0.0))
	button.add_theme_stylebox_override("hover", _card_style(character, 1.0))
	button.add_theme_stylebox_override("pressed", _card_style(character, 1.4))
	button.add_theme_stylebox_override("focus", _card_style(character, 0.7))
	button.pressed.connect(_on_character_pressed.bind(character))
	button.add_child(_make_portrait(character))
	button.add_child(_make_caption(character))
	return button


## 卡框按角色流派色染：一眼能分开四个人，也不至于像四个同模板的占位格。
func _card_style(character: PlayerData, emphasis: float) -> StyleBoxFlat:
	var accent := character.accent_color
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.07, 0.105, 0.90 + 0.03 * emphasis)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(accent.r, accent.g, accent.b, clampf(0.40 + 0.45 * emphasis, 0.0, 1.0))
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	# 悬停时向外扩一圈同色微光，代替「按钮变亮」那种通用反馈。
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.10 + 0.16 * emphasis)
	style.shadow_size = int(10 + 12 * emphasis)
	return style


## 立绘槽。定位靠锚点：占满卡片、上下各留边距、底下空出说明那一条。
func _make_portrait(character: PlayerData) -> Control:
	var holder := Control.new()
	holder.name = "Portrait"
	holder.anchors_preset = Control.PRESET_FULL_RECT
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = PORTRAIT_MARGIN
	holder.offset_top = PORTRAIT_MARGIN
	holder.offset_right = -PORTRAIT_MARGIN
	holder.offset_bottom = -(CAPTION_HEIGHT + PORTRAIT_MARGIN)
	return PortraitSlot.fill(holder, character.portrait, character.accent_color)


## 底部信息条：名字 + 气血/能量。做成半透明压条，立绘再亮也不会把字吃掉。
func _make_caption(character: PlayerData) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Caption"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = PORTRAIT_MARGIN
	panel.offset_right = -PORTRAIT_MARGIN
	panel.offset_top = -CAPTION_HEIGHT
	panel.offset_bottom = -6.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var accent := character.accent_color
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.06, 0.88)
	style.border_width_top = 1
	style.border_color = Color(accent.r, accent.g, accent.b, 0.65)
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = character.character_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", TITLE_FONT)
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 1.0))
	box.add_child(name_label)

	var stats := Label.new()
	stats.text = "气血 %d　能量 %d" % [character.base_max_hp, character.base_energy]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 14)
	stats.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78, 1.0))
	box.add_child(stats)

	return panel


func _on_character_pressed(character: PlayerData) -> void:
	var detail: Node = load(DETAIL_SCRIPT).new()
	detail.setup(character)
	add_child(detail)


func _on_back() -> void:
	GameManager.change_screen(GameManager.GameScreen.MAIN_MENU)
