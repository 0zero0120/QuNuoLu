class_name PotionManager
extends RefCounted

var potion_slots: Array = []
var max_slots: int = 3

func _init(slot_count: int = 3) -> void:
	max_slots = slot_count
	potion_slots.resize(max_slots)
	for i in range(max_slots):
		potion_slots[i] = null

func can_add_potion() -> bool:
	for slot in potion_slots:
		if slot == null:
			return true
	return false

func add_potion(potion: PotionData) -> int:
	for i in range(max_slots):
		if potion_slots[i] == null:
			potion_slots[i] = potion
			EventBus.potion_obtained.emit(potion)
			return i
	return -1

## 喝掉一瓶。指向性药水（is_targeted）必须点名一只活着的敌人，没点名就当没喝——
## 选目标选到一半按 ESC 取消，药水得原封不动留在槽里。
func use_potion(slot_index: int, bm: Variant = null, target: EnemyBase = null) -> PotionData:
	if slot_index < 0 or slot_index >= max_slots:
		return null
	var potion := potion_slots[slot_index] as PotionData
	if potion == null:
		return null
	if potion.is_targeted and not _is_valid_target(target):
		return null
	_apply_effect(potion, bm, target)
	potion_slots[slot_index] = null
	EventBus.potion_used.emit(potion, slot_index)
	return potion

## 目标算不算数：得是一只真的还站着的敌人。节点已经释放（spawn 进来的怪被清场）也算不成立。
static func _is_valid_target(target: EnemyBase) -> bool:
	return target != null and is_instance_valid(target) and target.is_alive

func _apply_effect(potion: PotionData, bm: Variant, target: EnemyBase = null) -> void:
	if bm:
		match potion.effect_type:
			"heal":
				bm.player.heal(int(potion.effect_value))
			"gain_strength":
				bm.player.add_status_effect(StatusEffect.Type.STRENGTH, int(potion.effect_value))
			"gain_dexterity":
				bm.player.add_status_effect(StatusEffect.Type.DEXTERITY, int(potion.effect_value))
			"gain_energy":
				bm.energy_system.add(int(potion.effect_value))
			"gain_block":
				bm.player.add_block(int(potion.effect_value))
			"deal_damage_all":
				for enemy in bm.get_alive_enemies():
					enemy.take_damage(int(potion.effect_value))
					EventBus.damage_dealt.emit(enemy, int(potion.effect_value), 0)
			"deal_damage_single":
				# 只打点名的那一只。走 take_damage 而不是直接减血：格挡和易伤都该参与
				# （和卡牌的单体伤害同一套规则）。
				target.take_damage(int(potion.effect_value))
				EventBus.damage_dealt.emit(target, int(potion.effect_value), 0)
			"gain_gold":
				GameManager.add_gold(int(potion.effect_value))
			"apply_poison":
				_apply_status_to_target(target, StatusEffect.Type.POISON, potion.effect_value)
			"apply_burn":
				_apply_status_to_target(target, StatusEffect.Type.BURN, potion.effect_value)
			"apply_weak":
				_apply_status_to_target(target, StatusEffect.Type.WEAK, potion.effect_value)
			"apply_vulnerable":
				_apply_status_to_target(target, StatusEffect.Type.VULNERABLE, potion.effect_value)
			"draw_cards":
				var scene := BattleManager.instantiate_card_scene()
				bm.card_pile.draw_to_hand(int(potion.effect_value), bm.hand_container, scene)
		bm._update_player_status_display()
		bm._check_battle_end()
		return

	# 战斗外没有「敌人」这个概念，指向性药水在这儿就是喝不出效果——上面 use_potion 那道
	# 关已经把这种情形挡掉了，这里留个空分支只是把话说明白。
	var pd := GameManager.player_data
	match potion.effect_type:
		"heal":
			pd.current_hp = mini(pd.current_hp + int(potion.effect_value), pd.max_hp)
		"gain_strength":
			pd.strength += int(potion.effect_value)
		"gain_dexterity":
			pd.dexterity += int(potion.effect_value)
		"gain_gold":
			GameManager.add_gold(int(potion.effect_value))
		"deal_damage_single", "apply_poison", "apply_burn", "apply_weak", "apply_vulnerable", "draw_cards":
			pass


## 药水给敌人上状态。和卡牌走的是同一套 add_status_effect（层数叠加、头顶图标自动刷新），
## 所以毒/灼烧的结算时机也跟卡牌下的毒一模一样，不需要在这儿另写一套。
## target 出不出得来由 use_potion 那道关保证（is_targeted 的药水没点名就当没喝）。
static func _apply_status_to_target(target: EnemyBase, type: StatusEffect.Type, value: float) -> void:
	if _is_valid_target(target):
		target.add_status_effect(type, int(value))
