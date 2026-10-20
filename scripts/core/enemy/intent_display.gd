class_name IntentDisplay
extends Control

@onready var intent_icon: Label = %IntentIcon
@onready var intent_texture: TextureRect = %IntentTexture
@onready var intent_value_label: Label = %IntentValueLabel

## 中毒意图用绿色药水瓶的像素图，不再用 emoji。🧪 是试管，玩家一眼看出「不是药』。
const POISON_ICON: String = "icon_venom_potion"

func show_intent(intent: IntentResource) -> void:
	show()
	var display_value: int = intent.value * intent.multiplier * maxi(1, intent.hit_count)
	intent_value_label.text = str(display_value)
	# 每次先把上一手的状态清干净：图标可能是字，也可能是图，不能两样一起露。
	intent_icon.show()
	intent_icon.text = ""
	intent_texture.hide()
	intent_texture.texture = null
	match intent.intent_type:
		IntentResource.IntentType.ATTACK:
			intent_icon.text = "⚔"
		IntentResource.IntentType.DEFEND:
			intent_icon.text = "🛡"
		IntentResource.IntentType.BUFF:
			intent_icon.text = "⬆"
		# 减益这一格不能一律用「⬇」：中毒和灼烧是直接扣血、无视格挡，
		# 用同一个下箭头玩家分不出「上状态」和「这一下真的会掉血」。
		IntentResource.IntentType.DEBUFF:
			if intent.status_effect_type == StatusEffect.Type.POISON:
				intent_icon.hide()
				intent_texture.texture = IconFactory.get_icon(POISON_ICON)
				intent_texture.show()
			else:
				intent_icon.text = _debuff_glyph(intent.status_effect_type)
		IntentResource.IntentType.SUMMON:
			intent_icon.text = "👥"
		# 蓄力怪放大招那一手：换个图标，玩家一眼能认出「这一下不是平砍」。
		IntentResource.IntentType.SPECIAL:
			intent_icon.text = "💥"
		# 诅咒塞牌：这一手不掉血，往你牌堆里塞废牌，图标得和伤害区分开。
		IntentResource.IntentType.CURSE:
			intent_icon.text = "☠"
		_:
			intent_icon.text = "?"
	# 图标上的数是这一手的总伤（多段攻击读得出疼不疼），但读不出「分几次打」——
	# 格挡和护体是按段吃的，这个差别得让玩家能看见，所以悬浮里写清单段与段数。
	tooltip_text = intent.get_description()

## 减益意图按具体状态分开。毒走真正的绿色药水瓶图（IconFactory.icon_venom_potion），
## 和敌人身上的「☠」状态图标不是一回事——那格讲的是现状，这格讲的是这一手要干什么。
func _debuff_glyph(type: StatusEffect.Type) -> String:
	match type:
		StatusEffect.Type.BURN:
			return "🔥"
		StatusEffect.Type.WEAK:
			return "🔻"
		StatusEffect.Type.VULNERABLE:
			return "🎯"
		_:
			return "⬇"

func hide_intent() -> void:
	hide()
