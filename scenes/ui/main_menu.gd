class_name MainMenu
extends Control

const SUBMENU_SCRIPT := "res://scripts/ui/submenu_screen.gd"
const SUB_PAGE_SCRIPT := "res://scripts/ui/sub_page.gd"
const SAVE_SLOT_SCRIPT := "res://scripts/ui/save_slot_screen.gd"

## 遗物收集按稀有度分组，每组配杀戮尖塔那句说明文案。
const RELIC_TIERS := [
	{"rarity": RelicData.RelicRarity.STARTER, "header": "初始", "desc": "角色初始携带的遗物。"},
	{"rarity": RelicData.RelicRarity.COMMON, "header": "普通", "desc": "很容易找到的弱小遗物。"},
	{"rarity": RelicData.RelicRarity.UNCOMMON, "header": "罕见", "desc": "比普通遗物更强大也更少见的遗物。"},
	{"rarity": RelicData.RelicRarity.RARE, "header": "稀有", "desc": "很少出现、能扭转局势的遗物。"},
	{"rarity": RelicData.RelicRarity.BOSS, "header": "BOSS", "desc": "击败首领后获得的遗物。"},
]

const POTION_TIERS := [
	{"rarity": PotionData.PotionRarity.COMMON, "header": "普通", "desc": "尖塔中最常见的药水。"},
	{"rarity": PotionData.PotionRarity.UNCOMMON, "header": "罕见", "desc": "比普通药水更强大也更少见的药水。"},
	{"rarity": PotionData.PotionRarity.RARE, "header": "稀有", "desc": "极少出现的独特且强大的药水。"},
]

const ENEMY_TIERS := [
	{"tier": EnemyData.EnemyTier.NORMAL, "header": "普通敌人", "desc": "在尖塔里会遇到的寻常敌人。"},
	{"tier": EnemyData.EnemyTier.ELITE, "header": "精英敌人", "desc": "盘踞中层、比寻常敌人更棘手的敌人。"},
	{"tier": EnemyData.EnemyTier.BOSS, "header": "BOSS", "desc": "镇守层末的强大敌人。"},
]


@onready var plaque_image: TextureRect = %PlaqueImage


func _ready() -> void:
	UIBackground.apply(self, "main_menu")
	# 匾额只是标题的底衬：图没落位时**什么都不做**，上面那行书法字照样摆在那儿
	# （不至于开一个空框，也不至于让标题消失）。
	var plaque := UIBackground.load_or_null("title_plaque")
	if plaque != null:
		plaque_image.texture = plaque
	var list := $MenuList
	list.get_node("ContinueButton").pressed.connect(_on_continue)
	list.get_node("StartButton").pressed.connect(_on_start)
	list.get_node("CodexButton").pressed.connect(_on_codex)
	list.get_node("StatsButton").pressed.connect(_on_stats)
	list.get_node("SettingsButton").pressed.connect(_on_settings)
	list.get_node("QuitButton").pressed.connect(_on_quit)
	$MenuList/ContinueButton.disabled = not _has_any_save()


func _has_any_save() -> bool:
	for slot in range(GameManager.SAVE_SLOT_COUNT):
		if GameManager.has_save(slot):
			return true
	return false


func _on_continue() -> void:
	_open_save_slots("load")


func _on_start() -> void:
	_open_save_slots("new")


func _open_save_slots(mode: String) -> void:
	var screen: SaveSlotScreen = load(SAVE_SLOT_SCRIPT).new()
	screen.setup(mode)
	add_child(screen)


func _on_codex() -> void:
	_open_submenu("百科大全", [
		{"title": "卡牌总览", "desc": "浏览全部卡牌", "on_press": _show_codex_cards,
			"illustration": UIBackground.load_or_null("events/forgotten_library")},
		{"title": "遗物收集", "desc": "浏览全部遗物", "on_press": _show_codex_relics,
			"illustration": UIBackground.load_or_null("events/treasure_chest")},
		{"title": "药水研究所", "desc": "浏览全部药水", "on_press": _show_codex_potions,
			"illustration": UIBackground.load_or_null("events/wandering_healer")},
		{"title": "敌人图鉴", "desc": "浏览全部敌人", "on_press": _show_codex_enemies,
			"illustration": UIBackground.load_or_null("events/mist_gate")},
	])


func _on_stats() -> void:
	_open_submenu("统计内容", [
		{"title": "角色数据", "desc": "查看角色战绩", "on_press": _show_stats_character,
			"illustration": UIBackground.load_or_null("events/mirror_pool")},
		{"title": "历史记录", "desc": "查看历史对局", "on_press": _show_stats_history,
			"illustration": UIBackground.load_or_null("events/stele_grove")},
	])


func _on_settings() -> void:
	_open_submenu("设定", [
		{"title": "游戏设定", "desc": "调整游戏参数", "on_press": _show_settings_game,
			"illustration": UIBackground.load_or_null("events/still_shrine")},
		{"title": "操作设置", "desc": "调整按键与操作", "on_press": _show_settings_controls,
			"illustration": UIBackground.load_or_null("events/old_smithy")},
		{"title": "制作名单", "desc": "看看是谁做的", "on_press": _show_settings_credits,
			"illustration": UIBackground.load_or_null("events/stele_grove")},
	])


func _on_quit() -> void:
	get_tree().quit()


func _open_submenu(title: String, items: Array) -> void:
	var screen: Node = load(SUBMENU_SCRIPT).new()
	screen.setup(title, items)
	add_child(screen)


func _open_sub_page(title: String, fill: Callable) -> void:
	var page: Node = load(SUB_PAGE_SCRIPT).new()
	page.setup(title, fill)
	add_child(page)


# --- 百科大全 ---

func _show_codex_cards() -> void:
	var page := CodexCardPage.new()
	page.setup_page("卡牌总览")
	add_child(page)


func _show_codex_relics() -> void:
	var page := CodexGridPage.new()
	page.setup_groups("遗物收集", _build_relic_groups())
	add_child(page)


func _show_codex_potions() -> void:
	var page := CodexGridPage.new()
	page.setup_groups("药水研究所", _build_potion_groups())
	add_child(page)


func _show_codex_enemies() -> void:
	var page := CodexGridPage.new()
	page.setup_groups("敌人图鉴", _build_enemy_groups())
	add_child(page)


func _build_relic_groups() -> Array:
	var mp := GameManager.meta_progress
	var groups: Array = []
	for tier: Dictionary in RELIC_TIERS:
		var entries: Array = []
		for relic: RelicData in DataManager.relic_database.values():
			if relic.rarity != tier["rarity"]:
				continue
			entries.append({
				"name": relic.relic_name,
				"icon": ArtIcons.load_or_null(relic.get_icon_path()),
				"color": relic.get_color(),
				"desc": relic.description,
				"known": mp == null or mp.has_obtained_relic(relic.relic_id),
			})
		_append_group(groups, tier, entries)
	return groups


func _build_potion_groups() -> Array:
	var mp := GameManager.meta_progress
	var groups: Array = []
	for tier: Dictionary in POTION_TIERS:
		var entries: Array = []
		for potion: PotionData in DataManager.potion_database.values():
			if potion.rarity != tier["rarity"]:
				continue
			entries.append({
				"name": potion.potion_name,
				"icon": ArtIcons.load_or_null(potion.get_icon_path()),
				"color": potion.get_color(),
				"desc": potion.description,
				"known": mp == null or mp.has_found_potion(potion.potion_id),
			})
		_append_group(groups, tier, entries)
	return groups


func _build_enemy_groups() -> Array:
	var mp := GameManager.meta_progress
	var groups: Array = []
	for tier: Dictionary in ENEMY_TIERS:
		var entries: Array = []
		for enemy: EnemyData in DataManager.enemy_database.values():
			# 变身第二形态不进图鉴：它不是玩家会独立遇到的一只怪，是别人换的一件衣服。
			# 摆出来会凭空多一条「从没见过」的灰条目，计数也跟着虚高。
			if enemy.tier != tier["tier"] or enemy.pool_hidden:
				continue
			entries.append({
				"name": enemy.display_name,
				"icon": enemy.portrait,
				"color": _enemy_color(enemy.tier),
				"desc": _enemy_desc(enemy),
				"known": mp == null or mp.has_seen_enemy(enemy.enemy_id),
			})
		_append_group(groups, tier, entries)
	return groups


## 图鉴条目正文：数值 + 那一句机制说明。机制这句是「反伤」「复活」「蓄力」这类东西唯一的
## 书面出处——状态图标只在战斗里看得见，光靠「生命 250」玩家没法预判下只会撞上什么。
func _enemy_desc(enemy: EnemyData) -> String:
	var desc := "生命 %d\n金币 %d-%d" % [
		enemy.max_hp, enemy.gold_reward_min, enemy.gold_reward_max]
	if not enemy.mechanic_desc.is_empty():
		desc += "\n" + enemy.mechanic_desc
	return desc


## 该稀有度暂时没有内容也照样建组——档位要一直摆着，后续扩卡池时自动填进来。
func _append_group(groups: Array, tier: Dictionary, entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))
	groups.append({
		"header": tier["header"],
		"desc": tier["desc"],
		"entries": entries,
	})


func _enemy_color(tier: int) -> Color:
	match tier:
		EnemyData.EnemyTier.ELITE: return Color(0.68, 0.45, 0.88)
		EnemyData.EnemyTier.BOSS: return Color(0.90, 0.42, 0.20)
	return Color(0.62, 0.62, 0.72)


# --- 统计内容 ---

func _show_stats_character() -> void:
	var page := StatsCharacterPage.new()
	page.setup_page("角色数据")
	add_child(page)


func _show_stats_history() -> void:
	var page := RunHistoryPage.new()
	page.setup_page("历史记录")
	add_child(page)


# --- 设定 ---

## 前两张卡进的是**同一个页面**，只是默认停在不同页签——照杀戮尖塔那张设定界面。
func _open_settings_screen(tab: int) -> void:
	var screen := SettingsScreen.new()
	screen.setup(tab)
	add_child(screen)


func _show_settings_game() -> void:
	_open_settings_screen(SettingsScreen.TAB_GAME)


func _show_settings_controls() -> void:
	_open_settings_screen(SettingsScreen.TAB_CONTROLS)


func _show_settings_credits() -> void:
	_open_sub_page("制作名单", func(page: SubPage) -> void:
		page.add_note("待实现：制作名单"))
