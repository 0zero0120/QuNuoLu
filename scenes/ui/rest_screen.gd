class_name RestScreen
extends Control

@onready var heal_button: Button = $VBoxContainer/HealButton
@onready var upgrade_button: Button = $VBoxContainer/UpgradeButton
@onready var result_label: Label = $VBoxContainer/ResultLabel
@onready var leave_button: Button = $VBoxContainer/LeaveButton

func _ready() -> void:
	UIBackground.apply(self, "rest")
	EventBus.rest_site_entered.emit()
	# 二选一：用过哪一项锁进存档，重进不再给一次，结果文案也照旧。
	# HP 本身不用在这里恢复——它已经跟着上一次 save_run() 进存档了。
	var state := GameManager.ensure_node_state(_roll_state)
	var chosen := str(state.get("choice", ""))
	heal_button.disabled = not chosen.is_empty()
	upgrade_button.disabled = not chosen.is_empty()
	result_label.text = str(state.get("result_text", ""))
	heal_button.pressed.connect(_on_heal)
	upgrade_button.pressed.connect(_on_upgrade)
	leave_button.pressed.connect(_on_leave)

func _roll_state() -> Dictionary:
	return {"choice": "", "result_text": ""}

func _on_heal() -> void:
	var heal_amount := int(GameManager.player_data.max_hp * 0.3)
	# 走 GameManager.set_player_hp，全局横条上那行血量才跟着动。
	GameManager.set_player_hp(GameManager.player_data.current_hp + heal_amount)
	result_label.text = "恢复了 %d 点生命值！" % heal_amount
	_commit("heal")

## 升级不再替玩家随机抽一张：弹选卡器让玩家自己从牌组里挑，这是构筑的核心环节。
## 挑完之前不 _commit——中途关掉选卡器等于没用掉这次休息，还能改选「休息」。
func _on_upgrade() -> void:
	var candidates := _upgradable_cards()
	if candidates.is_empty():
		result_label.text = "没有可升级的卡牌。"
		return
	var picker_scene := load("res://scenes/ui/card_picker_screen.tscn") as PackedScene
	if picker_scene == null:
		return
	var picker := picker_scene.instantiate() as CardPickerScreen
	picker.setup(candidates, "选择一张卡牌升级")
	picker.card_chosen.connect(_on_upgrade_chosen)
	add_child(picker)

func _upgradable_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for card: CardData in GameManager.current_deck:
		if not card.upgraded:
			out.append(card)
	return out

func _on_upgrade_chosen(card: CardData) -> void:
	# 名字和整张牌都要在 upgrade() 之前留一份：那个方法会改名字、费用，
	# 浮层里「升级前」那张卡必须还是旧数据。
	var name_before := card.card_name
	var before := card.duplicate() as CardData
	var upgraded_ok := GameManager.upgrade_card(card)
	if upgraded_ok:
		result_label.text = "「%s」已升级！" % name_before
	else:
		result_label.text = "没有可升级的卡牌。"
	_commit("upgrade")
	if upgraded_ok:
		CardUpgradePreview.show_for(self, before, card)

## 二选一：选完两个按钮一起禁掉，并立刻落盘——回的血、升的卡当场是既成事实，
## 重进既不给再来一次，也不给把另一项也用了。
func _commit(choice: String) -> void:
	heal_button.disabled = true
	upgrade_button.disabled = true
	GameManager.node_state["choice"] = choice
	GameManager.node_state["result_text"] = result_label.text
	GameManager.save_run()

func _on_leave() -> void:
	GameManager.finish_node()
