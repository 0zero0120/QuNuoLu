class_name EnemyBase
extends Node2D

signal died
signal intent_determined(intent: IntentResource)

## 阵型写死：玩家在左（PlayerArea）、敌人在右（EnemyArea）。挨打往后（向右）退，
## 出手往前（向左）扑。换版面这两行要跟着改（player.gd 那边有一条对称的）。
const FLINCH_DIR: int = 1
const STRIKE_DIR: int = -1

@export var enemy_data: EnemyData
## 待机浮动/呼吸、受击闪白+后仰、出手前冲。和玩家共用同一份实现（见 FighterAnim）。
## 成员初始化时就建出来：没 attach 之前它的每个方法都会自己判空跳过。
var _anim: FighterAnim = FighterAnim.new()
var current_hp: int = 0
var current_block: int = 0
var strength: int = 0
var dexterity: int = 0
var status_effects: Array[StatusEffect] = []
var is_alive: bool = true
var ai_controller: EnemyAIController
## 本回合预告出去的那一招。玩家回合开始时算一次，敌人回合直接执行这一份，不再现算，
## 这样头顶图标写的就是真打出来的那一下。见 prepare_intent。
var current_intent: IntentResource = null
var _intent_player: Player = null
var _setup_done: bool = false
## 这场战斗已经召唤过几只。召唤限的是「整场累计」，不然一只召唤怪能把玩家耗到天荒地老。
var _summoned_count: int = 0
## 分裂过没有。分裂是一次性的：血量在阈值附近反复进出（先被打下去、又回不上来）不该反复炸。
var _has_split: bool = false
## 复活过没有。和分裂一样是一次性闸门——第二形态再被打到 0 血就是真死，
## 否则两只形态互相复活，这场架永远打不完。
var _has_revived: bool = false

func setup(data: EnemyData) -> void:
	if _setup_done:
		return
	_setup_done = true
	enemy_data = data
	current_hp = data.max_hp
	current_block = 0
	strength = 0
	dexterity = 0
	status_effects.clear()
	# 开场光环（反伤/护体/神器）在这里摆上：它们是这只怪的属性，不是某一回合的动作，
	# 所以第一帧就得让玩家看见图标。神器要最后加——它会挡掉后续的减益。
	var aura := {
		StatusEffect.Type.THORNS: data.starting_thorns,
		StatusEffect.Type.WARD: data.starting_ward,
		StatusEffect.Type.ARTIFACT: data.starting_artifact,
	}
	for type: int in aura:
		if int(aura[type]) > 0:
			add_status_effect(type, int(aura[type]))
	ai_controller = EnemyAIController.new()
	ai_controller.setup(data)
	add_child(ai_controller)
	ai_controller.intent_determined.connect(_on_intent_determined)
	_apply_sprite()
	_update_display()

## 换节点得先有父节点：实战里 spawn_enemy 是先 setup() 再挂进树（入树前 get_parent() 是 null，
## add_sibling 会报错），所以入树前只记下贴图，等 _ready() 再换。和 _refresh_intent_display
## 一样拿 is_node_ready() 当闸门。
func _ready() -> void:
	_apply_sprite()
	# 换完图再挂动态：attach 现查的就是换过之后那个节点（名字不变，见 ArtSwap）。
	# 召唤/分裂出来的小怪也走这里，所以「所有敌人都有待机」是白拿的。
	_anim.attach(self, "EnemySprite")
	_anim.start_idle()


## 「战斗动态效果」开关改了之后当场生效。只经营待机那一路——受击/出手是事件驱动的，
## 每次触发都现读开关，本来就不用管。
func set_motion_enabled(on: bool) -> void:
	if on:
		_anim.start_idle()
	else:
		_anim.stop_idle()

## 头顶那个方块在场景里是 ColorRect（占位色块），填了贴图就换成 TextureRect。
## 换图的动作和玩家自己那份一样，都在 ArtSwap 里——别在这儿重新写一遍。
func _apply_sprite() -> void:
	if enemy_data == null or enemy_data.sprite_path.is_empty():
		return
	ArtSwap.fill(self, "EnemySprite", load(enemy_data.sprite_path))

func take_damage(amount: int) -> int:
	if not is_alive:
		return 0
	var final_amount := amount
	if has_status_of_type(StatusEffect.Type.VULNERABLE):
		final_amount = int(ceil(float(amount) * 1.5))
	# 护体排在易伤之后、格挡之前：先算出「这一下本该挨多少」，再拿护体削掉一截，
	# 剩下的才轮到格挡抵。护体逐段生效，所以它天生克制多段攻击。
	# 持续伤害走 take_true_damage，故意不吃护体——那是双方都打不动时唯一的推进手段。
	var ward := get_total_status_value(StatusEffect.Type.WARD)
	if ward > 0:
		final_amount = maxi(0, final_amount - ward)
	var blocked: int = mini(current_block, final_amount)
	current_block -= blocked
	var hp_damage: int = final_amount - blocked
	current_hp = maxi(0, current_hp - hp_damage)
	_update_display()
	# 扣血和挡下的数这里都已经算好了，头顶那个数字直接用，不用再算一遍。
	# 数字挂在父节点上，所以下面 die() 的淡出动画不会把它一起带走。
	EventBus.damage_number_requested.emit(self, hp_damage, blocked, -1)
	# 受击反馈。真掉血才后退；被格挡全吃下来就只闪一下——盾接住了，人没退。
	if hp_damage > 0:
		_anim.flinch(FLINCH_DIR)
	elif blocked > 0:
		_anim.flash_only()
	print("[EnemyBase] take_damage: amount=%d, hp_damage=%d, current_hp=%d/%d, blocked=%d" % [amount, hp_damage, current_hp, enemy_data.max_hp, blocked])
	if current_hp <= 0:
		# 复活要排在 die() 之前：die() 一落地，胜利判定、击杀计数、淡出动画就都跑完了。
		if _try_revive():
			return hp_damage
		die()
		return hp_damage
	if _intent_player and ai_controller and ai_controller.check_phase_transition():
		# 刚被打进二阶段：本回合预告的那招作废，按激进池重算，图标当场换掉。
		# 这是「怪物特性」允许打破「一回合锁一次意图」的唯一口子。
		print("[EnemyBase] %s 进入二阶段，重算意图" % enemy_data.display_name)
		prepare_intent(_intent_player)
	# 分裂和二阶段是两回事，用 if 不用 elif：一只怪两样都填了就该两样都触发。
	_try_split()
	return hp_damage

## 无视格挡、也不吃易伤的直接扣血，中毒/灼烧这类持续伤害走这里。
## 和 take_damage 分开是因为语义不同：那一条代表「被攻击」，格挡和易伤都该参与；
## 持续伤害是「从里面烂掉」，举盾挡不住，也谈不上被打得更疼。
## dot_type 说明这一下是哪来的（StatusEffect.Type.POISON / BURN，-1 表示说不出），
## 只管表现——数字按它换色、音效按它换一个，结算一个字都不受影响。
func take_true_damage(amount: int, dot_type: int = -1) -> int:
	if not is_alive:
		return 0
	var dealt := maxi(0, amount)
	if dealt <= 0:
		return 0
	current_hp = maxi(0, current_hp - dealt)
	_update_display()
	EventBus.damage_number_requested.emit(self, dealt, 0, dot_type)
	if dot_type >= 0:
		EventBus.dot_ticked.emit(self, dot_type)
	# 不是被打飞，是从里面烂掉：只闪一下，不后退。
	_anim.flash_only()
	print("[EnemyBase] take_true_damage: %s, amount=%d, current_hp=%d/%d" % [
		enemy_data.display_name, dealt, current_hp, enemy_data.max_hp])
	if current_hp <= 0:
		# 中毒/灼烧也能把复活怪打到 0 血，这条路同样得放行。
		if _try_revive():
			return dealt
		die()
		return dealt
	# 毒也一样能把它打到分裂线以下，所以这条路也得查一遍。
	_try_split()
	return dealt

func add_block(amount: int) -> void:
	var final_amount := maxi(0, amount)
	current_block += final_amount
	_update_display()

func reset_block() -> void:
	current_block = 0
	_update_display()

func die() -> void:
	# take_damage 有重入保护，die 也得有，否则重复调用会重复发 enemy_defeated（击杀数会翻倍）。
	if not is_alive:
		return
	print("[EnemyBase] die: %s, is_alive was %s" % [enemy_data.display_name, is_alive])
	is_alive = false
	# 待机浮动先从半空中停回原位再淡出，不然是从「浮着」的位置开始往上飘的。
	_anim.stop_idle()
	current_intent = null
	_refresh_intent_display()
	EventBus.enemy_defeated.emit(self)
	died.emit()
	_play_death_animation()

func _play_death_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "position:y", position.y - 20.0, 0.4)
	tween.chain().tween_callback(func():
		if self and is_instance_valid(self):
			visible = false
			# 站位跟着一起收：敌位是 HBox，死掉的还占着 180 宽就会在队伍中间留一道空，
			# 后面的召唤也看不到这个位子空出来了。隐藏的 Control 不参与 Container 布局，
			# 收掉就等于把位子让回去（BattleManager.free_enemy_slots 也是照这个数的）。
			var slot := get_parent() as Control
			if slot:
				slot.visible = false
	)

func get_strength() -> int:
	return strength

func get_dexterity() -> int:
	return dexterity

func add_status_effect(type: StatusEffect.Type, value: int) -> void:
	match type:
		StatusEffect.Type.STRENGTH:
			strength += value
			_update_display()
			return
		StatusEffect.Type.DEXTERITY:
			dexterity += value
			_update_display()
			return

	# 神器：挡下接下来的几次减益，挡一次掉一层。排在力量/敏捷的特判之后——那两种是增益，
	# 不该被自己的神器吃掉；自己身上的仪式/护体/反伤同理。
	if StatusEffect.is_debuff(type) and has_status_of_type(StatusEffect.Type.ARTIFACT):
		reduce_status_effect(StatusEffect.Type.ARTIFACT, 1)
		print("[EnemyBase] %s 的神器挡下了 %d 层%s" % [
			enemy_data.display_name, value, StatusEffect.type_display_name(type)])
		return

	for existing in status_effects:
		if existing.type == type:
			existing.value += value
			_update_display()
			return

	var effect := StatusEffect.new()
	effect.type = type
	effect.value = value
	status_effects.append(effect)
	_update_display()

func remove_status_effect(type: StatusEffect.Type) -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		if status_effects[i].type == type:
			status_effects.remove_at(i)
	_update_display()

func reduce_status_effect(type: StatusEffect.Type, amount: int = 1) -> void:
	for effect in status_effects:
		if effect.type == type:
			effect.value -= amount
			if effect.value <= 0:
				status_effects.erase(effect)
			_update_display()
			return

func has_status_of_type(type: StatusEffect.Type) -> bool:
	match type:
		StatusEffect.Type.STRENGTH: return strength != 0
		StatusEffect.Type.DEXTERITY: return dexterity != 0
	for effect in status_effects:
		if effect.type == type and effect.value > 0:
			return true
	return false

func get_total_status_value(type: StatusEffect.Type) -> int:
	var total := 0
	for effect in status_effects:
		if effect.type == type:
			total += effect.value
	return total

func on_turn_start() -> void:
	# 仪式：每回合开始白拿一份力量，越拖越硬。和玩家侧同一套（player.gd 的 on_turn_start）。
	# 这里不刷新显示，函数末尾那次 _update_display 会一起带上。
	for effect in status_effects:
		if effect.type == StatusEffect.Type.RITUAL:
			strength += effect.value
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
	_update_display()

func on_turn_end() -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		var effect := status_effects[i]
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
	_update_display()

## 执行头顶预告的那一招。**这是个协程**：攻击类要先把「出手」演到扑出去那一刻，
## 才轮到伤害落地——动作和命中对得上。调用方（EnemyTurnState）必须 await 它。
## 不开「战斗动态效果」时所有 await 会同步通过，整条链路照旧当帧跑完。
func execute_intent(intent: IntentResource, player: Player) -> void:
	match intent.intent_type:
		IntentResource.IntentType.ATTACK, IntentResource.IntentType.SPECIAL:
			# 攻击的出手动作里已经含了蓄力，不再另外 gesture 一次。
			await _anim.strike(STRIKE_DIR)
			await _execute_attack(intent, player)
		IntentResource.IntentType.DEFEND:
			_anim.gesture()
			add_block(intent.value * intent.multiplier + dexterity)
		IntentResource.IntentType.BUFF:
			_anim.gesture()
			_apply_self_buff(intent)
		IntentResource.IntentType.DEBUFF:
			_anim.gesture()
			_apply_debuff_to_player(intent, player)
		IntentResource.IntentType.SUMMON:
			_anim.gesture()
			_execute_summon()
		IntentResource.IntentType.CURSE:
			_anim.gesture()
			_execute_curse(intent)


## 单段的伤害：含力量和虚弱，不含格挡。多段攻击的每一段都按这个数分别结算。
func _attack_damage(intent: IntentResource) -> int:
	var damage := intent.value * intent.multiplier + strength
	if has_status_of_type(StatusEffect.Type.WEAK):
		damage = int(ceil(float(damage) * 0.75))
	return damage


## 多段攻击一段一段打：每段单独吃格挡、单独弹伤害数字。合成一个总数打一下的话，
## 玩家看到的就是「18」而不是「6、6、6」，格挡和护体吃掉的量也对不上。
## 中途把人打死了就停手——take_damage 没有存活保护，接着打会重复发 died 信号。
##
## 段与段之间留一口气（和玩家出牌那边同一个节拍），玩家才数得清挨了几下。
func _execute_attack(intent: IntentResource, player: Player) -> void:
	var damage := _attack_damage(intent)
	var hits := maxi(1, intent.hit_count)
	var tree := get_tree()
	for i in hits:
		if not player.is_alive():
			break
		player.take_damage(damage)
		if i < hits - 1 and tree != null:
			await tree.create_timer(FighterAnim.hit_beat()).timeout


## 蓄力倒计时：还有几回合放大招，0 表示这一手就是那一下。
## 值由轮转位置推出来（见 EnemyAIController._next_scripted），所以是覆盖写、不走
## add_status_effect——那个语义是累加，倒计时攒起来就成了错误的天数。
func set_charge_countdown(turns: int) -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		if status_effects[i].type == StatusEffect.Type.CHARGE:
			status_effects.remove_at(i)
	if turns > 0:
		var effect := StatusEffect.new()
		effect.type = StatusEffect.Type.CHARGE
		effect.value = turns
		status_effects.append(effect)
	_update_display()

func _apply_self_buff(intent: IntentResource) -> void:
	add_status_effect(intent.status_effect_type, intent.value * intent.multiplier)

func _apply_debuff_to_player(intent: IntentResource, player: Player) -> void:
	player.add_status_effect(intent.status_effect_type, intent.value * intent.multiplier)


## 当前战斗。active_battle 是强引用，场景切走之后可能指着已释放的节点，统一走 GameManager 那道闸。
func _battle_manager() -> BattleManager:
	return GameManager.get_active_battle()


## 还剩几个空敌位。没有战斗上下文时（单测里裸挂一只敌人）按「位子管够」算——
## 否则召唤永远被判成不成立，连测都测不了。
func free_slots() -> int:
	var bm := _battle_manager()
	if bm == null:
		return BattleManager.MAX_ENEMY_SLOTS
	return bm.free_enemy_slots()


## 还能不能召唤：数据里填了召唤谁、次数没用完、场上还有空位，三条都满足才行。
func can_summon() -> bool:
	if enemy_data == null or enemy_data.summon_enemy_id.is_empty():
		return false
	if _summoned_count >= enemy_data.summon_max:
		return false
	return free_slots() > 0


## 叫帮手。位子不够或次数用完了就少叫几只甚至不叫——这一回合是空放，但不是错：
## 意图已经在头顶预告出去了（「锁一次」是战斗的规则），只能按预告执行。
func _execute_summon() -> void:
	if not can_summon():
		print("[EnemyBase] %s 想召唤但条件不满足（已召 %d/%d，空位 %d）" % [
			enemy_data.display_name, _summoned_count, enemy_data.summon_max, free_slots()])
		return
	var bm := _battle_manager()
	if bm == null:
		return
	var data := DataManager.get_enemy(enemy_data.summon_enemy_id)
	if data == null:
		push_warning("[EnemyBase] 召唤目标「%s」不在敌人库里，%s 这一招空放" % [
			enemy_data.summon_enemy_id, enemy_data.display_name])
		return
	var want: int = mini(enemy_data.summon_count, enemy_data.summon_max - _summoned_count)
	var count: int = mini(want, free_slots())
	for i in count:
		if bm.spawn_enemy(GameManager.scale_enemy_for_run(data)) == null:
			break
	_summoned_count += count
	print("[EnemyBase] %s 召唤了 %d 只 %s（累计 %d/%d）" % [
		enemy_data.display_name, count, data.display_name, _summoned_count, enemy_data.summon_max])


## 诅咒塞牌：往玩家这一局的**战斗牌堆**里塞打不出去的废牌。
## 只进 CardPile，绝不进 GameManager.current_deck——那是存档里那份「玩家真正的牌组」，
## 写进去这场打完就留下了，整副牌越玩越烂，还得为旧存档写迁移；走战斗牌堆的话
## 打完这一场随战斗一起消失，存档零迁移成本。
## to_draw = true 塞进抽牌堆顶：玩家下一抽就摸得到，机制当场就能被看见。
func _execute_curse(intent: IntentResource) -> void:
	var count := intent.value * intent.multiplier
	if count <= 0 or intent.insert_card_id.is_empty():
		return
	var card := DataManager.get_card(intent.insert_card_id)
	if card == null:
		push_warning("[EnemyBase] 诅咒牌「%s」不在卡库里，%s 这一招空放" % [
			intent.insert_card_id, enemy_data.display_name])
		return
	var bm := _battle_manager()
	if bm == null or bm.card_pile == null:
		return
	for _i in count:
		bm.card_pile.add_to_deck(card, true)
	# 塞进手牌就算「见过这张牌」：诅咒不是能抽到的东西，不给它记一笔的话，
	# 百科里它永远点不亮，「集齐所有卡」的成就也就永远拿不到。
	GameManager.mark_cards_seen([card])
	print("[EnemyBase] %s 往玩家牌堆塞了 %d 张「%s」" % [enemy_data.display_name, count, card.card_name])


## 血量归零时的一线生机：换成另一套数据接着打（刑天断首再起）。
## 挂点在 take_damage / take_true_damage 判死的那一刻，**不能**挂 die()——die() 身后拖着
## 一串「真的死了」的副作用（is_alive=false 立刻判胜、enemy_defeated 计数、淡出动画把敌位
## 藏掉、EndState 结算奖励），挂那儿第二形态永远出不来，玩家会直接看到「打完收工」。
func _try_revive() -> bool:
	if _has_revived or enemy_data == null or enemy_data.revive_enemy_id.is_empty():
		return false
	# 第二形态也得走一遍本局缩放。第一形态是开场组队时拿 scale_enemy_for_run 生成出来的，
	# 直接读库里那一份原始数据的话，第 3 章的变身 BOSS 会带着第 1 章的血量站起来。
	var data := GameManager.scale_enemy_for_run(DataManager.get_enemy(enemy_data.revive_enemy_id))
	if data == null:
		push_warning("[EnemyBase] 复活目标「%s」不在敌人库里，%s 就此倒下" % [
			enemy_data.revive_enemy_id, enemy_data.display_name])
		return false
	_has_revived = true
	var was := enemy_data.display_name
	# 血量比例写在**第一形态**身上（「我复活时带着几成血回来」），所以得在 _reinit_as
	# 把 enemy_data 换成第二形态之前先取出来。
	var ratio := clampf(enemy_data.revive_hp_ratio, 0.0, 1.0)
	_reinit_as(data, ratio)
	# 头顶那招是第一形态算的，换了套招就得当场换掉：不重算的话玩家会照着旧图标做决定，
	# 敌人回合却打出第二形态的一手。
	if _intent_player:
		prepare_intent(_intent_player)
	print("[EnemyBase] %s 复活变身为 %s（%d 血）" % [was, enemy_data.display_name, current_hp])
	return true


## 换一套数据重新装配。先清 _setup_done 那道闸门——它管的是「同一个节点别重复初始化」，
## 而这里正好是要拿新数据重来一遍。召唤/分裂/复活三个计数器也归零：那是「这场战斗里做过
## 几次」，换了个身体就是新的一只，不该把第一形态的账接着记（否则第二形态再也召不出帮手）。
func _reinit_as(data: EnemyData, hp_ratio: float = 1.0) -> void:
	_setup_done = false
	if ai_controller:
		# 先摘再 free：queue_free 是延迟的，旧控制器还挂在这个名字上，
		# setup() 里紧接着 add_child 的那个新控制器就会被改名成 xxx2。
		remove_child(ai_controller)
		ai_controller.queue_free()
		ai_controller = null
	_summoned_count = 0
	_has_split = false
	setup(data)
	if hp_ratio < 1.0:
		current_hp = maxi(1, int(round(float(current_hp) * hp_ratio)))
		# setup() 里那次 _update_display 是按满血画的，改完血量得再画一遍。
		_update_display()
	# 第一形态的意图池彻底作废：current_intent 指着旧数据里的一条资源。
	current_intent = null


## 血量掉到分裂线以下就裂开，只裂一次。位子不够就少裂几只。
## 新裂出来的小怪这一回合不动——敌人回合的遍历用的是进场时的快照（见 EnemyTurnState），
## 而且它们头顶的意图要等下一个玩家回合开始才预告。
func _try_split() -> void:
	if _has_split or enemy_data == null or enemy_data.split_enemy_id.is_empty():
		return
	if enemy_data.split_hp_threshold <= 0.0:
		return
	if float(current_hp) / float(enemy_data.max_hp) > enemy_data.split_hp_threshold:
		return
	_has_split = true

	var bm := _battle_manager()
	if bm == null:
		return
	var data := DataManager.get_enemy(enemy_data.split_enemy_id)
	if data == null:
		push_warning("[EnemyBase] 分裂目标「%s」不在敌人库里，%s 裂不开" % [
			enemy_data.split_enemy_id, enemy_data.display_name])
		return
	var count: int = mini(enemy_data.split_count, free_slots())
	for i in count:
		if bm.spawn_enemy(GameManager.scale_enemy_for_run(data)) == null:
			break
	print("[EnemyBase] %s 分裂出 %d 只 %s" % [enemy_data.display_name, count, data.display_name])

func _update_display() -> void:
	if has_node("NameLabel"):
		# 以前这行没写，场景里那个「敌人」是写死的默认文本。场上一只时看不出来，
		# 一队三只全是「敌人」，谁是谁根本分不清。
		var name_label: Label = get_node("NameLabel")
		name_label.text = enemy_data.display_name if enemy_data else "敌人"
	if has_node("HPBar"):
		var bar: ColorRect = get_node("HPBar")
		var ratio: float = float(current_hp) / float(enemy_data.max_hp)
		bar.offset_right = -55.0 + 110.0 * ratio
		if ratio > 0.6:
			bar.color = Color(0.2, 0.8, 0.3, 1)
		elif ratio > 0.3:
			bar.color = Color(0.9, 0.8, 0.2, 1)
		else:
			bar.color = Color(0.9, 0.2, 0.2, 1)
	if has_node("HPText"):
		var hp_text: Label = get_node("HPText")
		hp_text.text = "%d/%d" % [current_hp, enemy_data.max_hp]
	if has_node("BlockLabel"):
		var block_label: Label = get_node("BlockLabel")
		if current_block > 0:
			block_label.text = "🛡 %d" % current_block
		else:
			block_label.text = ""
	if has_node("StatusLabel"):
		var status_label: Label = get_node("StatusLabel")
		var parts: Array[String] = []
		if strength > 0:
			parts.append("💪%d" % strength)
		if dexterity > 0:
			parts.append("⚡%d" % dexterity)
		for effect in status_effects:
			if effect.value > 0:
				parts.append("%s%d" % [effect.get_icon(), effect.value])
		status_label.text = " ".join(parts)
		var tooltips: Array[String] = []
		if strength > 0:
			tooltips.append("力量 +%d" % strength)
		if dexterity > 0:
			tooltips.append("敏捷 +%d" % dexterity)
		for effect in status_effects:
			if effect.value > 0:
				tooltips.append(effect.get_tooltip())
		status_label.tooltip_text = "\n".join(tooltips)
		status_label.mouse_filter = Control.MOUSE_FILTER_STOP
		if parts.size() > 0:
			status_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		else:
			status_label.add_theme_color_override("font_color", Color.WHITE)

func _on_intent_determined(intent: IntentResource) -> void:
	intent_determined.emit(intent)
	EventBus.enemy_intent_changed.emit(self, intent)

func get_next_intent(player: Player) -> IntentResource:
	if ai_controller:
		return ai_controller.get_next_intent(player)
	return null

## 玩家回合开始时算一次意图：存进 current_intent，顺带写进头顶那个图标。
## 敌人回合就执行这一份，不再现算——「预告的就是真打的那一下」。
func prepare_intent(player: Player) -> void:
	_intent_player = player
	current_intent = get_next_intent(player)
	_refresh_intent_display()

func _refresh_intent_display() -> void:
	# setup() 是入树前调的，那时候 %IntentIcon 还没绑上，只能等节点就绪。
	if not is_node_ready():
		return
	var display := get_node_or_null("IntentDisplay") as IntentDisplay
	if display == null:
		return
	if current_intent:
		display.show_intent(current_intent)
	else:
		display.hide_intent()
