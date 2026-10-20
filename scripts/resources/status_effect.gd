class_name StatusEffect
extends RefCounted

enum Type {
	STRENGTH,
	DEXTERITY,
	WEAK,
	VULNERABLE,
	RITUAL,
	POISON,
	BURN,
	CHARGE,
	THORNS,
	WARD,
	ARTIFACT
}

## 持续伤害类状态：层数就是每回合扣的血，结算时层数 -1，无视格挡。
## 中毒在自己回合开始结算，灼烧在自己回合结束结算——两者只是时机不同。
const DOT_TYPES: Array[Type] = [Type.POISON, Type.BURN]

## 减益：能被「神器」挡下的那几种。力量/敏捷在 EnemyBase.add_status_effect 里先被特判掉了，
## 仪式/护体/反伤/神器都是增益，蓄力是怪自己的节拍表——都不算减益。
const DEBUFF_TYPES: Array[Type] = [Type.WEAK, Type.VULNERABLE, Type.POISON, Type.BURN]

static func is_dot(type: Type) -> bool:
	return type in DOT_TYPES

static func is_debuff(type: Type) -> bool:
	return type in DEBUFF_TYPES

var type: Type
var value: int
var duration: int = -1
var temporary: bool = false

func get_icon() -> String:
	match type:
		Type.STRENGTH: return "💪"
		Type.DEXTERITY: return "⚡"
		Type.WEAK: return "🔻"
		Type.VULNERABLE: return "🎯"
		Type.RITUAL: return "⬆"
		Type.POISON: return "☠"
		Type.BURN: return "🔥"
		Type.CHARGE: return "⏳"
		Type.THORNS: return "🌵"
		Type.WARD: return "🧱"
		Type.ARTIFACT: return "🔱"
	return "?"

func get_display_name() -> String:
	return type_display_name(type)

## 只要一个类型名的地方也得能拿到（日志里光打数字读不懂）。实例方法转发到这里，
## 两边的名字只写一份。
static func type_display_name(kind: Type) -> String:
	match kind:
		Type.STRENGTH: return "力量"
		Type.DEXTERITY: return "敏捷"
		Type.WEAK: return "虚弱"
		Type.VULNERABLE: return "易伤"
		Type.RITUAL: return "仪式"
		Type.POISON: return "中毒"
		Type.BURN: return "灼烧"
		Type.CHARGE: return "蓄力"
		Type.THORNS: return "反伤"
		Type.WARD: return "护体"
		Type.ARTIFACT: return "神器"
	return "?"

func get_tooltip() -> String:
	var base := get_display_name()
	match type:
		Type.STRENGTH: base += " +%d：攻击伤害 +%d" % [value, value]
		Type.DEXTERITY: base += " +%d：技能格挡 +%d" % [value, value]
		Type.WEAK: base += " %d：造成的伤害降低 25%%" % value
		Type.VULNERABLE: base += " %d：受到的伤害增加 50%%" % value
		Type.RITUAL: base += " %d：每回合获得 %d 点力量" % [value, value]
		Type.POISON: base += " %d：回合开始时失去 %d 点生命（无视格挡）" % [value, value]
		Type.BURN: base += " %d：回合结束时失去 %d 点生命（无视格挡）" % [value, value]
		Type.CHARGE: base += " %d：还有 %d 回合放出蓄力大招" % [value, value]
		Type.THORNS: base += " %d：每次被攻击，攻击者受到 %d 点伤害" % [value, value]
		Type.WARD: base += " %d：每次受到的攻击伤害减少 %d 点（持续伤害无视）" % [value, value]
		Type.ARTIFACT: base += " %d：接下来 %d 次减益无效" % [value, value]
	if temporary:
		base += "（本回合）"
	return base

func get_color() -> Color:
	match type:
		Type.STRENGTH: return Color(0.9, 0.35, 0.25, 1)
		Type.DEXTERITY: return Color(0.35, 0.55, 0.9, 1)
		Type.WEAK: return Color(0.6, 0.35, 0.7, 1)
		Type.VULNERABLE: return Color(0.9, 0.6, 0.15, 1)
		Type.RITUAL: return Color(0.75, 0.25, 0.8, 1)
		Type.POISON: return Color(0.45, 0.78, 0.35, 1)
		Type.BURN: return Color(0.95, 0.45, 0.15, 1)
		Type.CHARGE: return Color(0.85, 0.6, 0.2, 1)
		Type.THORNS: return Color(0.75, 0.45, 0.2, 1)
		Type.WARD: return Color(0.55, 0.65, 0.8, 1)
		Type.ARTIFACT: return Color(0.95, 0.8, 0.3, 1)
	return Color.WHITE

func decrement() -> bool:
	if duration > 0:
		duration -= 1
	return duration == 0
