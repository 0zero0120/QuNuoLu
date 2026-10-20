class_name ShopScreen
extends Control

@onready var card_container: HBoxContainer = %CardContainer
@onready var relic_container: HBoxContainer = %RelicContainer
@onready var remove_button: Button = %RemoveCardButton
@onready var leave_button: Button = %LeaveButton

const CARD_COUNT: int = 3
const RELIC_COUNT: int = 2
## 和事件页 buy_potion 那句一字不差：同一个「买不起」不该在两屏有两种说法。
const _NOT_ENOUGH_GOLD: String = "你的金币不够。"

func _ready() -> void:
	UIBackground.apply(self, "shop")
	_display_items()
	_refresh_remove_button()
	remove_button.pressed.connect(_on_remove_card)
	leave_button.pressed.connect(_on_leave)

## 货架抽一次就锁进存档：重进看到同一批货、同一批已购状态，
## 既不给重新随机的机会，也不给把同一件商品买第二次的机会。
func _roll_state() -> Dictionary:
	var cards: Array = []
	var rolled := DataManager.get_weighted_random_cards(
		CARD_COUNT, DataManager.get_balance().card_rarity_weights)
	GameManager.mark_cards_seen(rolled)
	for card: CardData in rolled:
		# 价钱跟着快照一起落盘。重进时按 balance 现算会和当初扣的钱对不上——
		# 中间改过 balance，或者楼层变了，看到的就是另一套价。
		cards.append({"card_id": card.card_id, "bought": false, "price": _price_for_card(card)})

	var exclude_ids: Array[String] = []
	for relic: RelicData in GameManager.current_relics:
		exclude_ids.append(relic.relic_id)
	var relics: Array = []
	for _i in range(RELIC_COUNT):
		var relic := DataManager.get_random_relic(-1, exclude_ids)
		if relic:
			relics.append({"relic_id": relic.relic_id, "bought": false, "price": _price_for_relic(relic)})

	var state := {"cards": cards, "relics": relics, "removals": 0}
	state["removal_price"] = _price_for_removal(state)
	return state

## 稀有度打底、楼层上浮。取不到配置就回落到一个中间价，宁可价不对也不能崩在这一屏。
func _price_for_card(card: CardData) -> int:
	var bal := DataManager.get_balance()
	if bal == null:
		return 50
	var base := int(bal.card_price_by_rarity.get(
		CardData.rarity_to_string(int(card.rarity)), 50))
	return _marked_up(base, bal)

func _price_for_relic(relic: RelicData) -> int:
	var bal := DataManager.get_balance()
	if bal == null:
		return 150
	var base := int(bal.relic_price_by_rarity.get(
		RelicData.rarity_to_string(int(relic.rarity)), 150))
	return _marked_up(base, bal)

func _marked_up(base: int, bal: BalanceConfig) -> int:
	var floors := maxi(0, GameManager.current_floor - 1)
	return int(round(float(base) * (1.0 + bal.shop_price_floor_step * floors)))

## 删卡：起步价 + 这家店里已经删掉的张数。同一家店删第二张就更贵。
func _price_for_removal(state: Dictionary) -> int:
	var bal := DataManager.get_balance()
	var base := bal.card_removal_base_price if bal else 75
	var step := bal.card_removal_price_step if bal else 25
	return base + step * int(state.get("removals", 0))

func _display_items() -> void:
	var state := GameManager.ensure_node_state(_roll_state)
	for entry: Dictionary in state.get("cards", []):
		card_container.add_child(_make_card_button(entry))
	for entry: Dictionary in state.get("relics", []):
		relic_container.add_child(_make_relic_button(entry))

func _make_card_button(entry: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 150)
	var card := DataManager.get_card(str(entry.get("card_id", "")))
	if card == null:
		btn.disabled = true
		return btn
	var price := int(entry.get("price", 0))
	# 边框跟角色走，和卡面上那张牌一套映射。三种状态一起覆盖：只写 normal 的话鼠标一悬停就闪回默认灰底。
	# 按钮上的字保持原样不动——那是「牌名 + 价格」拼的一段，价格不是卡面文字，跟着稀有度变色反而看不懂。
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, _card_style(card.get_character_border_color()))
	btn.tooltip_text = "%s\n%s\n费用: %d 金币" % [card.card_name, card.description_template, price]
	if bool(entry.get("bought", false)):
		btn.text = "已购买"
		btn.disabled = true
	else:
		btn.text = "%s\n%d 金币" % [card.card_name, price]
		btn.pressed.connect(_on_buy_card.bind(card, entry, btn))
	return btn

## 商店卡牌按钮的底板，形状和百科卡片的圆角对齐（底中性、边跟角色）。
func _card_style(border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CardData.PANEL_BG
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box

## 和卡牌商品同高同宽、同一套底板（边框换遗物稀有度色）——一屏货架看起来才是一套。
## 内容 = 图标 + 名字 + 状态（价格 / 已购买），状态那个 Label 名字定死，_mark_bought 靠它改字。
func _make_relic_button(entry: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 150)
	var relic := DataManager.get_relic(str(entry.get("relic_id", "")))
	if relic == null:
		btn.disabled = true
		return btn
	var price := int(entry.get("price", 0))
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, _card_style(relic.get_color()))
	btn.tooltip_text = "%s\n%s\n费用: %d 金币" % [relic.relic_name, relic.description, price]

	var body := VBoxContainer.new()
	body.name = "Body"
	body.anchors_preset = Control.PRESET_FULL_RECT
	body.anchor_right = 1.0
	body.anchor_bottom = 1.0
	body.offset_left = 8.0
	body.offset_top = 8.0
	body.offset_right = -8.0
	body.offset_bottom = -8.0
	# 不 IGNORE 的话容器会吃掉点击，按钮点不动（同 submenu_screen 的卡片）。
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	# 4 而不是 6：84 的图标已经把格子塞得差不多了，名字换行也还有余量。
	body.add_theme_constant_override("separation", 4)
	btn.add_child(body)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(CodexIcon.make_relic_slot(relic, 84))
	body.add_child(icon_center)

	body.add_child(_make_chip_text(relic.relic_name, 13, Color(1, 1, 1)))
	var status := _make_chip_text("", 12, Color(1.0, 0.85, 0.2))
	status.name = "StatusLabel"
	body.add_child(status)

	if bool(entry.get("bought", false)):
		status.text = "已购买"
		btn.disabled = true
	else:
		status.text = "%d 金币" % price
		btn.pressed.connect(_on_buy_relic.bind(relic, entry, btn))
	return btn


func _make_chip_text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _on_buy_card(card: CardData, entry: Dictionary, btn: Button) -> void:
	if not GameManager.spend_gold(int(entry.get("price", 0))):
		_show_feedback(_NOT_ENOUGH_GOLD)
		return
	GameManager.add_card_to_deck(card)
	_mark_bought(entry, btn)

func _on_buy_relic(relic: RelicData, entry: Dictionary, btn: Button) -> void:
	if not GameManager.spend_gold(int(entry.get("price", 0))):
		_show_feedback(_NOT_ENOUGH_GOLD)
		return
	GameManager.add_relic(relic)
	_mark_bought(entry, btn)
	_show_relic_obtained(relic)

## 买完立刻落盘：这一次购买已经花掉的金币和进包的东西当场就是既成事实。
func _mark_bought(entry: Dictionary, btn: Button) -> void:
	entry["bought"] = true
	btn.disabled = true
	# 卡牌商品仍是 btn.text；遗物商品的内容在 Body 里，改那个状态 Label。
	var status := btn.get_node_or_null("Body/StatusLabel") as Label
	if status != null:
		status.text = "已购买"
	else:
		btn.text = "已购买"
	_refresh_remove_button()
	GameManager.save_run()

## 删卡服务：把整副牌组摊开让玩家挑一张。买不起也不把按钮禁掉——变灰等于堵死出路，
## 点下去会告诉玩家差在哪（和事件页同一个道理）。
func _refresh_remove_button() -> void:
	var price := int(GameManager.node_state.get("removal_price", 0))
	remove_button.text = "移除一张卡牌 (%d 金币)" % price
	remove_button.disabled = GameManager.current_deck.is_empty()

func _on_remove_card() -> void:
	var price := int(GameManager.node_state.get("removal_price", 0))
	if GameManager.current_gold < price:
		_show_feedback(_NOT_ENOUGH_GOLD)
		return
	var picker_scene := load("res://scenes/ui/card_picker_screen.tscn") as PackedScene
	if picker_scene == null:
		return
	var picker := picker_scene.instantiate() as CardPickerScreen
	picker.setup(GameManager.current_deck, "选择一张卡牌移除")
	picker.card_chosen.connect(_on_card_removed)
	add_child(picker)

## 挑中才扣钱——中途关掉选卡器不算用过这项服务。
func _on_card_removed(card: CardData) -> void:
	var price := int(GameManager.node_state.get("removal_price", 0))
	if not GameManager.spend_gold(price):
		_show_feedback(_NOT_ENOUGH_GOLD)
		return
	GameManager.remove_card_from_deck(card)
	GameManager.node_state["removals"] = int(GameManager.node_state.get("removals", 0)) + 1
	GameManager.node_state["removal_price"] = _price_for_removal(GameManager.node_state)
	_refresh_remove_button()
	GameManager.save_run()

func _show_relic_obtained(relic_data: RelicData) -> void:
	var scene := load("res://scenes/ui/relic_obtain_screen.tscn") as PackedScene
	if scene == null:
		return
	var overlay = scene.instantiate()
	overlay.setup(relic_data)
	add_child(overlay)

## 摆在货架下面那一片空白里（y≈920~990），压在「离开商店」按钮上方。
## 不能照抄事件页的居中偏移——那个位置在商店正好盖住遗物那一排。
func _show_feedback(msg: String) -> void:
	ScreenFeedback.show_message(self, msg, Rect2(-280.0, 380.0, 560.0, 70.0))

func _on_leave() -> void:
	GameManager.finish_node()
