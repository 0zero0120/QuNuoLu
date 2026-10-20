class_name PlayerData
extends Resource

@export var character_id: String = "jianke"
@export var character_name: String = "剑客"
## 界面上摆出来的先后。**不能靠 character_database 的遍历次序**——那个是按文件名排序加载的
## （见 DataManager._load_resources），排出来是「蛊师/剑客/傩师/武僧」，跟设计次序对不上。
## 要调整角色出场顺序就改这个数；展示处一律走 DataManager.characters_in_order()。
@export var order_index: int = 0
@export var base_max_hp: int = 80
@export var base_energy: int = 3
@export var starting_relic_id: String = "burning_blood"
## 本角色的流派色。专属卡的卡面底色由它染出来——牌面、百科、商店共用一个来源。
@export var accent_color: Color = Color(0.65, 0.65, 0.70, 1.0)
@export var starting_deck_ids: Array[String] = [
	"strike", "strike", "strike", "strike", "strike",
	"defend", "defend", "defend", "defend",
	"bash"
]
@export var portrait: Texture2D

var current_hp: int = 0
var max_hp: int = 0
var gold: int = 99
var strength: int = 0
var dexterity: int = 0
var potion_slots: int = 3

func reset_for_new_run() -> void:
	current_hp = base_max_hp
	max_hp = base_max_hp
	var bal := DataManager.get_balance()
	gold = bal.starting_gold if bal else 99
	strength = 0
	dexterity = 0
