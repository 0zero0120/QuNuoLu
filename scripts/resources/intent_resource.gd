class_name IntentResource
extends Resource

enum IntentType { ATTACK, DEFEND, BUFF, DEBUFF, SUMMON, SPECIAL, CURSE }

@export var intent_type: IntentType = IntentType.ATTACK
@export var value: int = 0
@export var multiplier: int = 1
## 这一段攻击打几下。1 是平砍，>1 是多段攻击：每一段单独结算格挡、单独弹一个伤害数字，
## 所以「6 点 ×3」和「18 点 ×1」对玩家的意义完全不同（前者被格挡和护体吃得更狠，也更怕反伤）。
## 别拿 multiplier 兼职这件事——value * multiplier 在 AI 评分、意图图标、卡面描述里
## 都是「这一手的数值」，改语义会静默毁掉那几处。
@export var hit_count: int = 1
@export var status_effect_type: StatusEffect.Type = StatusEffect.Type.STRENGTH
## CURSE 用的那张牌的 id。塞几张由 value * multiplier 定，和别的意图一个口径——
## 于是第 3 章的诅咒多一张，跟着 _scale_intents 的章数倍率一起涨。
@export var insert_card_id: String = ""
@export var icon_texture: Texture2D
@export var description_template: String = ""

func get_description() -> String:
	var desc := description_template
	desc = desc.replace("{value}", str(value * multiplier))
	if desc.contains("{card}"):
		var card: CardData = DataManager.get_card(insert_card_id)
		# 查不到就写「诅咒」两个字：数据填错了，玩家那儿也不该出现一个空的引号。
		desc = desc.replace("{card}", card.card_name if card else "诅咒")
	var hits := _hit_text()
	if desc.contains("{hits}"):
		return desc.replace("{hits}", hits)
	if hits.is_empty():
		return desc
	# 模板忘了写 {hits}：光说「造成 6 点伤害」会被读成只打一下，把段数补在句号前。
	if desc.ends_with("。"):
		return desc.substr(0, desc.length() - 1) + hits + "。"
	return desc + hits

func _hit_text() -> String:
	return " ×%d 次" % hit_count if hit_count > 1 else ""

## 这一次攻击满打满算多少点。多段攻击的总伤，AI 评分和「最重一拳」的尺子都得用这个。
func total_damage() -> int:
	return value * multiplier * maxi(1, hit_count)

func get_icon() -> Texture2D:
	return icon_texture
