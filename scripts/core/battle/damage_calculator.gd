class_name DamageCalculator
extends RefCounted

enum DamageType { PHYSICAL, MAGICAL, TRUE }

## 力量只加在本来就有伤害的牌上，和 CardData.get_display_damage 同一套规矩——
## 否则 base_damage=0 的牌在有力量时会凭空打出力点数的伤害。
static func calculate_damage(base_damage: int, strength: int, target_block: int, _dmg_type: int = DamageType.PHYSICAL) -> int:
	var raw: int = base_damage + strength if base_damage > 0 else 0
	if target_block <= 0:
		return maxi(0, raw)
	var effective: int = maxi(0, raw - target_block)
	return effective

static func calculate_block_damage(base_damage: int, target_block: int) -> Dictionary:
	var blocked: int = mini(base_damage, target_block)
	var hp_damage: int = base_damage - blocked
	return {"hp_damage": hp_damage, "block_damage": blocked}

## 同上：敏捷只加在本来就有格挡的牌上。
static func calculate_block_gain(base_block: int, dexterity: int) -> int:
	if base_block <= 0:
		return 0
	return maxi(0, base_block + dexterity)
