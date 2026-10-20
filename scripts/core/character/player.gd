class_name Player
extends Node2D

var current_hp: int = 80
var max_hp: int = 80
var current_block: int = 0
var strength: int = 0
var dexterity: int = 0
var _temp_strength: int = 0
var _temp_dexterity: int = 0
var status_effects: Array[StatusEffect] = []
var block_does_not_expire: bool = false

## 阵型是写死的：PlayerArea 在左（anchor 0.05~0.46）、EnemyArea 在右（0.54~0.95）。
## 所以玩家挨打一律向左退、出手一律向右扑。换版面的话这两行要跟着改
## （enemy_base.gd 那边有一条对称的，方向刚好相反）。
const FLINCH_DIR: int = -1
const STRIKE_DIR: int = 1

signal hp_changed(current: int, maximum: int)
signal block_changed(current: int)
signal strength_changed(value: int)
signal dexterity_changed(value: int)
signal status_effects_changed
signal died

## 待机浮动/呼吸、受击闪白+后仰、出手前冲。和敌人共用同一份实现（见 FighterAnim）。
## 成员初始化时就建出来：没 attach 之前它的每个方法都会自己判空跳过，不用在这里再挡一道。
var _anim: FighterAnim = FighterAnim.new()

func reset_for_battle(pd: PlayerData) -> void:
	current_hp = pd.current_hp
	max_hp = pd.max_hp
	current_block = 0
	strength = pd.strength
	dexterity = pd.dexterity
	_temp_strength = 0
	_temp_dexterity = 0
	status_effects.clear()
	block_does_not_expire = false
	_update_display()

## 玩家自己的立绘。和敌人头顶那块走同一套（ArtSwap），没图的角色留着占位色块。
## 换完图再挂动态：attach 现查的就是换过之后那个节点（名字不变，见 ArtSwap）。
func _ready() -> void:
	var pd := GameManager.player_data
	if pd != null:
		ArtSwap.fill(self, "PlayerSprite", pd.portrait, pd.accent_color)
	_anim.attach(self, "PlayerSprite")
	_anim.start_idle()


## 「战斗动态效果」开关改了之后当场生效。只经营待机那一路——受击/出手是事件驱动的，
## 每次触发都现读开关，本来就不用管。
func set_motion_enabled(on: bool) -> void:
	if on:
		_anim.start_idle()
	else:
		_anim.stop_idle()


## 出手的那一下前冲。**故意不 await**：卡飞向敌人已经在做视觉引导了，玩家这一下是补个动作，
## 没必要让出牌链整条变成协程（那会把三个输入入口一起拖下水）。
func strike_at_enemies() -> void:
	_anim.strike(STRIKE_DIR)

func take_damage(amount: int) -> int:
	var final_amount := amount
	if has_status_of_type(StatusEffect.Type.VULNERABLE):
		final_amount = int(ceil(float(amount) * 1.5))
	var blocked: int = mini(current_block, final_amount)
	current_block -= blocked
	var hp_damage: int = final_amount - blocked
	current_hp = maxi(0, current_hp - hp_damage)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	block_changed.emit(current_block)
	# 扣血和挡下的数这里都已经算好了，头顶那个数字直接用，不用再算一遍。
	EventBus.damage_number_requested.emit(self, hp_damage, blocked, -1)
	# 受击反馈。真掉血才后退；被格挡全吃下来就只闪一下——盾接住了，人没退。
	if hp_damage > 0:
		_anim.flinch(FLINCH_DIR)
	elif blocked > 0:
		_anim.flash_only()
	print("[Player] take_damage: amount=%d, hp_damage=%d, current_hp=%d/%d, blocked=%d" % [amount, hp_damage, current_hp, max_hp, blocked])
	_update_display()
	if current_hp <= 0:
		died.emit()
	return hp_damage

## 无视格挡、也不吃易伤的直接扣血，中毒/灼烧这类持续伤害走这里。
## 和 take_damage 分开是因为语义不同：那一条代表「有人打你一下」，格挡和易伤都该参与；
## 持续伤害是「从里面烂掉」，举盾挡不住，也谈不上被打得更疼。
## dot_type 说明这一下是哪来的（StatusEffect.Type.POISON / BURN，-1 表示说不出），
## 只管表现——数字按它换色、音效按它换一个，结算一个字都不受影响。
func take_true_damage(amount: int, dot_type: int = -1) -> int:
	var dealt := maxi(0, amount)
	if dealt <= 0:
		return 0
	current_hp = maxi(0, current_hp - dealt)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	EventBus.damage_number_requested.emit(self, dealt, 0, dot_type)
	if dot_type >= 0:
		EventBus.dot_ticked.emit(self, dot_type)
	# 不是被打飞，是从里面烂掉：只闪一下，不后退。退那一下是「挨了一记」的意思，
	# 中毒不该长成那样。
	_anim.flash_only()
	print("[Player] take_true_damage: amount=%d, current_hp=%d/%d" % [dealt, current_hp, max_hp])
	_update_display()
	if current_hp <= 0:
		died.emit()
	return dealt

func heal(amount: int) -> void:
	current_hp = mini(current_hp + amount, max_hp)
	EventBus.player_hp_changed.emit(current_hp, max_hp)
	_update_display()

func add_block(amount: int) -> void:
	var final_amount := maxi(0, amount)
	current_block += final_amount
	block_changed.emit(current_block)
	_update_display()

func reset_block() -> void:
	if block_does_not_expire:
		return
	current_block = 0
	block_changed.emit(0)
	_update_display()

func get_strength() -> int:
	return strength

func get_dexterity() -> int:
	return dexterity

func add_status_effect(type: StatusEffect.Type, value: int, temporary: bool = false) -> void:
	if value <= 0:
		return

	match type:
		StatusEffect.Type.STRENGTH:
			strength += value
			if temporary:
				_temp_strength += value
			strength_changed.emit(strength)
			return
		StatusEffect.Type.DEXTERITY:
			dexterity += value
			if temporary:
				_temp_dexterity += value
			dexterity_changed.emit(dexterity)
			return
		_:
			pass

	for existing in status_effects:
		if existing.type == type:
			existing.value += value
			if existing.duration > 0:
				existing.duration += 1
			status_effects_changed.emit()
			return

	var effect := StatusEffect.new()
	effect.type = type
	effect.value = value
	effect.temporary = temporary
	status_effects.append(effect)
	status_effects_changed.emit()

func remove_status_effect(type: StatusEffect.Type) -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		if status_effects[i].type == type:
			status_effects.remove_at(i)
	status_effects_changed.emit()

func reduce_status_effect(type: StatusEffect.Type, amount: int = 1) -> void:
	for effect in status_effects:
		if effect.type == type:
			effect.value -= amount
			if effect.value <= 0:
				status_effects.erase(effect)
			status_effects_changed.emit()
			return

func has_status_of_type(type: StatusEffect.Type) -> bool:
	match type:
		StatusEffect.Type.STRENGTH: return get_strength() != 0
		StatusEffect.Type.DEXTERITY: return get_dexterity() != 0
	for effect in status_effects:
		if effect.type == type and effect.value > 0:
			return true
	return false

## 身上某种状态现在有几层。没有就是 0。敌人 AI 判「这条毒是起还是续」要用。
func get_status_value(type: StatusEffect.Type) -> int:
	for effect in status_effects:
		if effect.type == type:
			return effect.value
	return 0

func on_turn_start() -> void:
	for effect in status_effects:
		if effect.type == StatusEffect.Type.RITUAL:
			strength += effect.value
			strength_changed.emit(strength)
	for i in range(status_effects.size() - 1, -1, -1):
		var effect := status_effects[i]
		# 中毒在自己回合开始时结算：层数就是这一下扣的血，扣完层数 -1。
		if effect.type == StatusEffect.Type.POISON:
			take_true_damage(effect.value, StatusEffect.Type.POISON)
			effect.value -= 1
			if effect.value <= 0:
				status_effects.remove_at(i)
			continue
		if effect.decrement():
			status_effects.remove_at(i)
	status_effects_changed.emit()

func on_turn_end() -> void:
	strength -= _temp_strength
	_temp_strength = 0
	strength_changed.emit(strength)
	dexterity -= _temp_dexterity
	_temp_dexterity = 0
	dexterity_changed.emit(dexterity)

	for i in range(status_effects.size() - 1, -1, -1):
		var effect := status_effects[i]
		if effect.temporary:
			status_effects.remove_at(i)
			continue
		match effect.type:
			StatusEffect.Type.WEAK, StatusEffect.Type.VULNERABLE:
				effect.value -= 1
				if effect.value <= 0:
					status_effects.remove_at(i)
			# 灼烧在自己回合结束时结算，和中毒只是时机不同。
			StatusEffect.Type.BURN:
				take_true_damage(effect.value, StatusEffect.Type.BURN)
				effect.value -= 1
				if effect.value <= 0:
					status_effects.remove_at(i)
			_:
				if effect.decrement():
					status_effects.remove_at(i)
	status_effects_changed.emit()

func save_state_to_player_data(pd: PlayerData) -> void:
	pd.current_hp = current_hp

func is_alive() -> bool:
	return current_hp > 0

func _update_display() -> void:
	if has_node("PlayerHPBar"):
		var bar: ColorRect = get_node("PlayerHPBar")
		var ratio: float = float(current_hp) / float(max_hp)
		bar.offset_right = -55.0 + 110.0 * ratio
		if ratio > 0.6:
			bar.color = Color(0.2, 0.8, 0.3, 1)
		elif ratio > 0.3:
			bar.color = Color(0.9, 0.8, 0.2, 1)
		else:
			bar.color = Color(0.9, 0.2, 0.2, 1)
	if has_node("PlayerHPText"):
		var hp_text: Label = get_node("PlayerHPText")
		hp_text.text = "%d/%d" % [current_hp, max_hp]
	if has_node("PlayerNameLabel"):
		var name_label: Label = get_node("PlayerNameLabel")
		# 名字只认当前角色的数据。四个角色共用这一个战斗场景，写死「剑客」的话
		# 傩师/蛊师/武僧打起来头顶挂的还是剑客的名字。
		var parts: Array[String] = []
		var pd := GameManager.player_data
		if pd != null:
			parts.append(pd.character_name)
		if current_block > 0:
			# 盾牌就写这个字面量，别改回 \U 转义：Godot 的 \U 只吃 6 位十六进制，
			# `"\U0001f6e1"` 会被解成 U+01F6（Ƕ，长得像 H）+ 字面量 "e1"，
			# 界面上就显成「Hue120」那种乱码。别处（battle_manager 的格挡标签）也是字面量。
			parts.append("🛡%d" % current_block)
		name_label.text = "  ".join(parts)
