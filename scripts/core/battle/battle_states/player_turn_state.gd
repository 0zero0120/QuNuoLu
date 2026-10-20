class_name PlayerTurnState
extends State

var _card_signals_connected: bool = false
var _drag_hovered_enemy: EnemyBase = null
## 上一帧是不是正处在「给药水指目标」的状态。只是为了认出「刚进 / 刚出」这一个瞬间，
## 好把敌人高亮点起来、收回去——真正的事实只有一个来源，就是 bm.pending_potion_slot。
var _potion_targeting: bool = false

func enter(_data: Dictionary = {}) -> void:
	var bm: BattleManager = state_machine.get_parent()
	bm.turn_number += 1
	if bm.end_turn_button:
		bm.end_turn_button.disabled = false

	bm.player.on_turn_start()
	for enemy in bm.enemies:
		if enemy.is_alive:
			enemy.on_turn_start()

	# 状态先衰减完再算意图，否则图标上的数会按上回合的增益/虚弱来估。
	for enemy in bm.enemies:
		if enemy.is_alive:
			enemy.prepare_intent(bm.player)

	var base_energy := GameManager.player_data.base_energy
	bm.energy_system.reset(base_energy)

	# turn_started 放在能量重置**之后**：挂在这个时机上的遗物可能是「本回合多一点能量」
	# （灵泉），而 reset() 会把 current_energy 整个重写一遍——早一步发就等于白加。
	EventBus.turn_started.emit(bm.turn_number)

	# 每场战斗只发一次，同样排在 reset 之后：首回合一次的加能量遗物（铜锣）也得加在
	# reset 写死的 current_energy 上，而不是被它清掉。
	if bm.turn_number == 1:
		EventBus.first_turn_started.emit(bm.turn_number)

	var card_scene := BattleManager.instantiate_card_scene()
	bm.card_pile.draw_to_hand(bm.cards_per_turn, bm.hand_container, card_scene)

	_connect_hand_cards(bm)
	bm.selected_card = null
	bm._update_hand_playable()
	bm._check_battle_end()
	# 药水槽「本回合能不能点」也要在这里开回来：上一场如果在多段结算途中打完，
	# _begin_resolve 关了它，而 _end_resolve 看状态已经不是 PlayerTurn 就不会再开，
	# 于是下一场开局点药水没反应，直到玩家先打出一张牌才恢复。
	if bm.state_machine.get_current_state_name() == "PlayerTurn":
		bm.set_potions_active(true)

## 「正在等玩家指目标」有两种来源：选中了一张单体牌，或者刚点了瓶指向性药水。
## 两者的手感刻意做成一样——敌人泛金等你去点，指到谁谁变绿。
func _process(_delta: float) -> void:
	var bm: BattleManager = state_machine.get_parent()
	if bm.pending_potion_slot >= 0:
		if not _potion_targeting:
			_potion_targeting = true
			# 举着药水的时候手上不能还攥着一张选中的牌：两处都会给敌人打高亮，会互相打架。
			_clear_selection(bm)
			_highlight_enemies(bm)
		_check_drag_hover(bm)
		return
	if _potion_targeting:
		_potion_targeting = false
		_clear_drag_hover(bm)
	if _drag_hovered_enemy:
		return
	var card := bm.selected_card
	if card and card.card_data \
			and card.card_data.target_type == CardData.TargetType.SINGLE_ENEMY:
		_check_drag_hover(bm)

func _connect_hand_cards(bm: BattleManager) -> void:
	for child in bm.hand_container.get_children():
		if child is Card:
			if not child.card_clicked.is_connected(_on_card_clicked):
				child.card_clicked.connect(_on_card_clicked)
			if not child.card_drag_started.is_connected(_on_card_drag_started):
				child.card_drag_started.connect(_on_card_drag_started)
			if not child.card_drag_ended.is_connected(_on_card_drag_ended):
				child.card_drag_ended.connect(_on_card_drag_ended)

func _check_drag_hover(bm: BattleManager) -> void:
	var mouse_pos := bm.get_global_mouse_position()
	var enemy := _enemy_at_position(bm, mouse_pos, true)
	if enemy != _drag_hovered_enemy:
		if _drag_hovered_enemy:
			_drag_hovered_enemy.modulate = Color(1.0, 0.8, 0.3, 1)
		_drag_hovered_enemy = enemy
		if _drag_hovered_enemy:
			_drag_hovered_enemy.modulate = Color(0.3, 1.0, 0.4, 1)


## 这个状态的输入有三条路：鼠标点敌人、确认选牌（Enter）、数字键快选（1~9/0）。
## 走 StateMachine._input，也就是输入链的第一站，跑在界面控件前面——所以这里能先看到点击，
## 也因此**不能乱吃事件**：没命中敌人、没选中牌的时候必须原样放过去，否则点手牌、点按钮全会被吞掉。
func handle_input(event: InputEvent) -> void:
	var bm: BattleManager = state_machine.get_parent()

	# ESC 只用来取消选中（或者取消指目标）。有东西可取消的时候把它吃掉，
	# 免得顺手把暂停菜单一起弹出来。
	if event.is_action_pressed("ui_cancel"):
		if bm.pending_potion_slot >= 0:
			bm.pending_potion_slot = -1
			get_viewport().set_input_as_handled()
		elif bm.selected_card:
			_clear_selection(bm)
			get_viewport().set_input_as_handled()
		return

	# 确认选牌（默认 Enter）：把选中的那张打出去。没选中牌就不碰 Enter，弹窗里的按钮还要用它。
	if event.is_action_pressed("confirm_play"):
		if bm.selected_card:
			_confirm_selected(bm)
			get_viewport().set_input_as_handled()
		return

	# 点敌人：手上举着指向性药水时，点谁用谁；否则看选中的单体牌，点谁打谁。
	# 没命中敌人就把事件放过去——这一条和上面「不能乱吃事件」是同一个道理。
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		var enemy := _enemy_at_position(bm, _battle_pos_of(bm, click.position), true)
		if enemy == null:
			return
		if bm.pending_potion_slot >= 0:
			_use_pending_potion(bm, enemy)
			get_viewport().set_input_as_handled()
		elif bm.selected_card:
			play_hand_card_on(bm, bm.selected_card, enemy)
			get_viewport().set_input_as_handled()
		return

	if not SettingsManager.show_play_keys:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# 物理键优先，和设定页那边改键的记法保持一致。
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	var index := BattleManager.play_key_index(code)
	if index < 0:
		return

	var cards: Array[Card] = []
	for child in bm.hand_container.get_children():
		if child is Card:
			cards.append(child)
	# 手牌不足这么多张就当没按：按到空位不该吃掉这次按键。
	if index >= cards.size():
		return
	play_hand_card(bm, cards[index])
	get_viewport().set_input_as_handled()


## 点击、拖拽、数字键三个入口都先过这里决定「打谁」。
## 单体牌走不了这条路：它必须先有目标，见 _select_card / play_hand_card_on。
func _on_card_clicked(card: Card) -> void:
	var bm: BattleManager = state_machine.get_parent()
	# 点已经选中的那张＝取消选中。
	if bm.selected_card == card:
		_clear_selection(bm)
		return
	# 单体牌不管开关怎么设都得先指个目标，所以点一下只是选中，等着点敌人或按确认。
	if card.card_data.target_type == CardData.TargetType.SINGLE_ENEMY:
		if not bm.energy_system.can_spend(card.card_data.get_display_cost(bm.player)):
			return
		_select_card(bm, card)
		return
	# 其余牌不用指目标：开着「不需要确认」就点一下直接出去，关掉则先选中等确认。
	if SettingsManager.skip_confirm_single:
		play_hand_card(bm, card)
		return
	_select_card(bm, card)


## 选中一张手牌，进入「等你点敌人 / 按确认」的状态。场上敌人一起泛金提醒可以指目标。
func _select_card(bm: BattleManager, card: Card) -> void:
	if bm.selected_card and bm.selected_card != card and is_instance_valid(bm.selected_card):
		bm.selected_card.set_selected(false)
	bm.selected_card = card
	card.set_selected(true)
	if card.card_data.target_type == CardData.TargetType.SINGLE_ENEMY:
		_highlight_enemies(bm)


## 取消选中：牌子上的暖光、敌人身上的高亮、鼠标悬停过的那只，一起复位。
func _clear_selection(bm: BattleManager) -> void:
	if bm.selected_card and is_instance_valid(bm.selected_card):
		bm.selected_card.set_selected(false)
	bm.selected_card = null
	_clear_drag_hover(bm)


## 按「确认选牌」：把选中的牌打出去。单体牌没指定过目标就打第一个活着的（和数字键同一套兜底）。
func _confirm_selected(bm: BattleManager) -> void:
	var card := bm.selected_card
	if card == null or not is_instance_valid(card):
		return
	play_hand_card(bm, card)


## 不带目标地打出一张牌：能给自己的给自己、群体牌打全体、随机的随机、单体牌打第一个活着的敌人。
## 点击、拖拽、数字键三个入口都走这里，省得各写一份，日后改一处漏一处。
## 返回是否真的打出去了（能量不够、场上没人之类就返回 false）。
func play_hand_card(bm: BattleManager, card: Card) -> bool:
	# 多段结算期间锁死输入：一张牌正在一段一段地打，这中间再塞一张进去，
	# 两串结算会交错着往下走，血量和节拍全乱。等它走完再放行。
	if bm._resolving:
		return false
	if card == null or card.card_data == null:
		return false
	# 诅咒牌在点下去的那一刻就拦掉：手牌置灰只是外观，这里和 play_card 才是真拦得住的地方。
	if card.card_data.unplayable:
		return false
	if not bm.energy_system.can_spend(card.card_data.get_display_cost(bm.player)):
		return false

	match card.card_data.target_type:
		CardData.TargetType.SELF, CardData.TargetType.NONE:
			bm.play_card(card, bm.player)
		CardData.TargetType.ALL_ENEMIES:
			bm.play_card(card)
		CardData.TargetType.RANDOM_ENEMY:
			var alive := bm.get_alive_enemies()
			if alive.is_empty():
				return false
			bm.play_card(card, GameManager.rand_pick(alive))
		CardData.TargetType.SINGLE_ENEMY:
			var alive := bm.get_alive_enemies()
			if alive.is_empty():
				bm._check_battle_end()
				return false
			bm.play_card(card, alive[0])
		_:
			return false
	_clear_selection(bm)
	return true


## 把一张牌打在指定的那只敌人身上。点敌人、拖拽落在敌人身上两个入口都走这里。
## 返回是否真的打出去了。
func play_hand_card_on(bm: BattleManager, card: Card, enemy: EnemyBase) -> bool:
	if bm._resolving:
		return false
	if card == null or card.card_data == null or enemy == null:
		return false
	if card.card_data.unplayable:
		return false
	if not bm.energy_system.can_spend(card.card_data.get_display_cost(bm.player)):
		return false
	bm.play_card(card, enemy)
	_clear_selection(bm)
	return true


## 把待指目标的那瓶药水用在点中的这只敌人身上。药水的消耗和效果都归 PotionManager，
## 这里只管「点的是谁」——和卡牌的 play_hand_card_on 是同一个位置、同一套命中判定。
func _use_pending_potion(bm: BattleManager, enemy: EnemyBase) -> void:
	var slot := bm.pending_potion_slot
	bm.pending_potion_slot = -1
	_clear_drag_hover(bm)
	GameManager.use_potion(slot, bm, enemy)


func _on_card_drag_started(card: Card) -> void:
	var bm: BattleManager = state_machine.get_parent()
	if card.card_data.target_type == CardData.TargetType.SINGLE_ENEMY:
		if not bm.energy_system.can_spend(card.card_data.get_display_cost(bm.player)):
			return
		_select_card(bm, card)
		return
	play_hand_card(bm, card)


func _on_card_drag_ended(card: Card, drop_global_position: Vector2) -> void:
	var bm: BattleManager = state_machine.get_parent()
	if card.card_data.target_type != CardData.TargetType.SINGLE_ENEMY:
		return
	var enemy := _enemy_at_position(bm, drop_global_position, true)
	if enemy:
		play_hand_card_on(bm, card, enemy)
	else:
		# 没落在敌人身上，退回打第一个活着的（和数字键同一套兜底）。
		play_hand_card(bm, card)


## 鼠标事件里的位置是「视口坐标」，而敌人身上那圈判定框（_enemy_at_position）用的是战斗场景
## 自己的坐标。这里换算一下，换算方式跟引擎的 get_global_mouse_position() 一模一样。
## 用事件自带的位置、而不是回头去问「鼠标现在在哪」：处理的是哪一次点击，就按哪一次的位置判定。
func _battle_pos_of(bm: BattleManager, viewport_pos: Vector2) -> Vector2:
	return bm.get_global_transform_with_canvas().affine_inverse() * viewport_pos


func _enemy_at_position(bm: BattleManager, global_pos: Vector2, expanded: bool = false) -> EnemyBase:
	for enemy in bm.get_alive_enemies():
		var wrapper := enemy.get_parent() as Control
		if wrapper:
			var rect := wrapper.get_global_rect()
			if expanded:
				rect = rect.grow(30)
			if rect.has_point(global_pos):
				return enemy
	return null

func _highlight_enemies(bm: BattleManager) -> void:
	for enemy in bm.get_alive_enemies():
		enemy.modulate = Color(1.0, 0.8, 0.3, 1)

func _clear_drag_hover(bm: BattleManager) -> void:
	if _drag_hovered_enemy:
		_drag_hovered_enemy = null
	for enemy in bm.get_alive_enemies():
		enemy.modulate = Color.WHITE

func exit() -> void:
	var bm: BattleManager = state_machine.get_parent()
	_clear_selection(bm)
	# 举着药水的时候点了「结束回合」，这个状态就到此为止了：待指目标必须一起作废，
	# 否则敌人回合里 bm 还挂着那个槽号，下一回合玩家随手点个敌人就把药水喝了。
	bm.pending_potion_slot = -1
	_potion_targeting = false
