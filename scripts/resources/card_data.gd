class_name CardData
extends Resource

enum CardType { ATTACK, SKILL, ABILITY }
enum CardRarity { BASIC, COMMON, UNCOMMON, RARE }
enum TargetType { NONE, SINGLE_ENEMY, ALL_ENEMIES, SELF, RANDOM_ENEMY }

## 代码画的卡牌面板（百科卡片、商店按钮）的深色底。卡面内衬是 card.tscn 里另一个值——
## 那块底归场景管，这里只管代码画出来的。
const PANEL_BG := Color(0.10, 0.10, 0.15, 1.0)
## 通用牌（打击/防御）的边框色。专属牌染自己角色的流派色，通用的走这个中性钢灰。
const GENERIC_BORDER := Color(0.52, 0.52, 0.56, 1.0)

@export var card_id: String = ""
@export var card_name: String = "新卡牌"
## 这张牌属于哪个角色。空串是四角色通用的牌（打击、防御），
## 取值要和 resources/characters/ 下的 character_id 对上，写错了这张牌就谁都抽不到。
@export var character_id: String = ""
@export var card_type: CardType = CardType.ATTACK
@export var rarity: CardRarity = CardRarity.BASIC
@export var cost: int = 1
@export var description_template: String = ""
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var base_damage: int = 0
@export var base_block: int = 0
@export var base_magic_number: int = 0
@export var hit_count: int = 1
@export var upgrade_bonus_damage: int = 3
@export var upgrade_bonus_block: int = 3
@export var upgrade_bonus_magic: int = 0
@export var upgrade_bonus_cost: int = 0
@export var upgraded: bool = false
@export var exhaust_on_use: bool = false
@export var ethereal: bool = false
@export var innate: bool = false
@export var icon_texture: Texture2D
@export var status_on_target: String = ""
@export var status_on_self: String = ""
@export var status_temporary: bool = false
@export var special_effect: String = ""
@export var unlock_cost: int = 0
## 规则上就打不出去的死牌（诅咒）。和「能量不够所以现在打不了」是两回事：那个会随回合变，
## 这个是这张牌的属性。不新开 CardType.CURSE 是因为新类型要按「每种类型至少几张」补齐、
## 百科还得新开一页，代价远大于收益——牌面上写着一句不能打出就够了。
@export var unplayable: bool = false

## 这张牌能不能被玩家主动拿到（战斗奖励、商店、事件）。诅咒只能由敌人塞进战斗牌堆，
## 一旦漏进随机卡池，玩家的牌组会随着通关越滚越烂。
func is_obtainable() -> bool:
	return not unplayable

func get_display_cost(_owner: Node = null) -> int:
	return maxi(0, cost)

func is_x_cost() -> bool:
	return cost < 0

## 「这张牌本来就有这一项」才吃加成，力量/敏捷和升级加成都是。判空**必须排在升级加成之前**：
## upgrade_bonus_damage / _block 的默认值是 3（.tres 里不写就是这个数），先加再判空的话，
## base_damage = 0 的牌升级后 val 变成 3 > 0，判空拦不住——顺劈斩升级白送 3 点格挡，
## 侧步这种纯防御牌反过来会打敌人 3 点。卡面文字里还一个字都不提（模板没写 {block} 就不替换）。
## 以前力量/敏捷也是无条件加的，有敏捷时打任何一张牌都白送格挡，战吼这种 base_damage=0
## 的群攻牌会凭空打出力点数的伤害——同一个道理，只是当时只修了力量敏捷那半边。
func get_display_damage(owner: Node = null) -> int:
	var val: int = base_damage
	if val <= 0:
		return 0
	if upgraded:
		val += upgrade_bonus_damage
	if owner and owner.has_method("get_strength"):
		val += owner.get_strength()
	return maxi(0, val)

func get_display_block(owner: Node = null) -> int:
	var val: int = base_block
	if val <= 0:
		return 0
	if upgraded:
		val += upgrade_bonus_block
	if owner and owner.has_method("get_dexterity"):
		val += owner.get_dexterity()
	return maxi(0, val)

func get_status_amount() -> int:
	if base_magic_number > 0:
		var amount := base_magic_number
		if upgraded and upgrade_bonus_magic > 0:
			amount += upgrade_bonus_magic
		return amount
	return 1

func upgrade() -> void:
	if upgraded:
		return
	upgraded = true
	card_name += "+"
	if upgrade_bonus_cost > 0:
		cost = maxi(0, cost - upgrade_bonus_cost)

func get_description(owner: Node = null) -> String:
	var desc := description_template
	var dmg := get_display_damage(owner)
	var blk := get_display_block(owner)
	desc = desc.replace("{damage}", str(dmg))
	desc = desc.replace("{block}", str(blk))
	desc = desc.replace("{cost}", str(get_display_cost(owner)))
	desc = desc.replace("{magic}", str(get_status_amount()))
	return desc

func get_effects_on_target() -> Array[String]:
	var arr: Array[String] = []
	if not status_on_target.is_empty():
		for s in status_on_target.split("|"):
			arr.append(s)
	return arr

func has_effect_on_target() -> bool:
	return not status_on_target.is_empty()

func get_effects_on_self() -> Array[String]:
	var arr: Array[String] = []
	if not status_on_self.is_empty():
		for s in status_on_self.split("|"):
			arr.append(s)
	return arr

func has_effect_on_self() -> bool:
	return not status_on_self.is_empty()

static func rarity_to_string(rarity: int) -> String:
	match rarity:
		CardRarity.BASIC: return "BASIC"
		CardRarity.COMMON: return "COMMON"
		CardRarity.UNCOMMON: return "UNCOMMON"
		CardRarity.RARE: return "RARE"
	return "COMMON"


## 牌型的字符串写法，和 rarity_to_string() 同一套做法。遗物要认「只对攻击牌生效」时
## 就是拿它比的（见 RelicEffectResolver._card_matches）——枚举名直接当字符串用。
func type_to_string() -> String:
	match card_type:
		CardType.ATTACK: return "ATTACK"
		CardType.SKILL: return "SKILL"
		CardType.ABILITY: return "ABILITY"
	return "ATTACK"

func get_color() -> Color:
	match card_type:
		CardType.ATTACK: return Color(0.85, 0.25, 0.2, 1)
		CardType.SKILL: return Color(0.2, 0.45, 0.85, 1)
		CardType.ABILITY: return Color(0.2, 0.7, 0.3, 1)
	return Color.WHITE

## 卡牌边框装的是角色归属：专属牌染自己角色的流派色，通用牌（打击/防御）走中性钢灰，
## 「专属 / 通用」就是靠这两者对比出来的。归属写错查不到角色时也回中性，不会染出乱七八糟的颜色。
func get_character_border_color() -> Color:
	if character_id.is_empty():
		return GENERIC_BORDER
	var character := DataManager.get_character(character_id)
	if character == null:
		return GENERIC_BORDER
	return character.accent_color


## 卡面牌名的字色装的是稀有度——边框让位给角色之后，等级改由字色显现。
## 色值和从前那套边框色同源，只把基础/普通两档提亮一档：同一个颜色当 3px 边框还看得清，
## 写到 14px 字上就发糊了。
func get_text_color() -> Color:
	match rarity:
		CardRarity.BASIC: return Color(0.78, 0.72, 0.60, 1)
		CardRarity.COMMON: return Color(0.80, 0.80, 0.82, 1)
		CardRarity.UNCOMMON: return Color(0.45, 0.68, 1.0, 1)
		CardRarity.RARE: return Color(0.95, 0.70, 0.10, 1)
	return Color(0.80, 0.80, 0.80, 1)

func get_rarity_glow() -> Color:
	match rarity:
		CardRarity.BASIC: return Color(0.6, 0.55, 0.45, 0.15)
		CardRarity.COMMON: return Color(0.65, 0.65, 0.65, 0.2)
		CardRarity.UNCOMMON: return Color(0.3, 0.5, 1.0, 0.25)
		CardRarity.RARE: return Color(1.0, 0.75, 0.15, 0.3)
	return Color(1, 1, 1, 0.1)

func get_type_icon_text() -> String:
	match card_type:
		CardType.ATTACK: return "⚔"  # ⚔
		CardType.SKILL: return "◆"   # ◆
		CardType.ABILITY: return "✦" # ✦
	return "?"

## 类型图标的国风图目录，按**类型**（不是按卡）取图，三种类型三张。
## 图不在就返回路径，由 ArtIcons.load_or_null() 探到不存在、退回 IconFactory 的程序像素画
## ——缺图不是错误状态（同 PotionData.get_icon_path() 的口径）。
const TYPE_ICON_DIR := "res://assets/art/card_types/"

func get_type_icon_path() -> String:
	match card_type:
		CardType.ATTACK: return TYPE_ICON_DIR + "attack.png"
		CardType.SKILL: return TYPE_ICON_DIR + "skill.png"
		CardType.ABILITY: return TYPE_ICON_DIR + "ability.png"
	return ""


const ART_DIR := "res://assets/art/cards/"

## 卡面插画按 **card_id** 找，不按 card_name：傩师那批的 id 和名字是脱钩的
## （alchemy_furnace=桃符、cinder_shield=傩面、spark=松明），按名字命名会串。
## 图不在就返回路径，由 card.gd 那边探到文件不存在、悄悄不显示——缺图不是错误状态。
func get_art_path() -> String:
	if card_id.is_empty():
		return ""
	return ART_DIR + card_id + ".png"
