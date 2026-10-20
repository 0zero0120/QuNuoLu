class_name StatsCharacterPage
extends SubPage

## 统计内容 → 角色数据：总体统计（左右两栏）+ 角色进度 + 成就网格。
## 参考杀戮尖塔：上面是账号级汇总，下面是每个角色一行，最后是上锁/解锁的成就墙。
##
## 左栏是战绩类（时间、胜败、楼层、击杀），右栏是收集类（百科四页的发现度）+ 最快胜利。
## 成就的解锁状态来自 MetaProgress.unlocked_achievement_ids，评估在 GameManager.evaluate_achievements()。

const SLOT_SIZE := 76.0
const HEADER_COLOR := Color(0.92, 0.86, 0.72)
const VALUE_COLOR := Color(0.92, 0.80, 0.45)
const NAME_COLOR := Color(0.80, 0.79, 0.87)
const MUTED := Color(0.52, 0.50, 0.60)
const LOCKED_COLOR := Color(0.42, 0.42, 0.50)

var _flow: HFlowContainer


func setup_page(title: String) -> void:
	setup(title, _fill_page)


func _fill_page(_page: SubPage) -> void:
	_add_header("总体统计", "")
	add_content(_make_totals_row())

	add_content(_make_gap(26))
	_add_header("角色进度", "")
	_add_character_rows()

	add_content(_make_gap(26))
	_add_achievements()


# --- 总体统计 ---

func _make_totals_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)

	var mp := GameManager.meta_progress
	if mp == null:
		left.add_child(_make_stat_row("暂无数据", ""))
		return row

	left.add_child(_make_stat_row("总游戏时间", _format_duration(mp.stat_total("play_seconds"))))
	left.add_child(_make_stat_row("总胜利", "%d" % mp.stat_total("wins")))
	left.add_child(_make_stat_row("总死亡", "%d" % mp.stat_total("deaths")))
	left.add_child(_make_stat_row("总共爬过的楼层", "%d" % mp.stat_total("floors_climbed")))
	left.add_child(_make_stat_row("总共杀死的 Boss", "%d" % mp.stat_total("bosses_killed")))
	left.add_child(_make_stat_row("总共杀死的敌人", "%d" % mp.stat_total("enemies_killed")))

	right.add_child(_make_stat_row("发现的卡牌", _discovered_text(
		DataManager.card_database, func(card: CardData) -> bool: return mp.has_seen_card(card.card_id))))
	right.add_child(_make_stat_row("发现的药水", _discovered_text(
		DataManager.potion_database, func(potion: PotionData) -> bool: return mp.has_found_potion(potion.potion_id))))
	right.add_child(_make_stat_row("发现的遗物", _discovered_text(
		DataManager.relic_database, func(relic: RelicData) -> bool: return mp.has_obtained_relic(relic.relic_id))))
	right.add_child(_make_stat_row("遇见过的敌人", _discovered_text(
		DataManager.enemy_database,
		func(enemy: EnemyData) -> bool: return mp.has_seen_enemy(enemy.enemy_id),
		func(enemy: EnemyData) -> bool: return not enemy.pool_hidden)))

	var best := mp.fastest_win()
	right.add_child(_make_stat_row("最快胜利", "暂无" if best <= 0 else _format_duration(best)))

	return row


## 分子按数据库里实际存在的条目数，不是 seen 列表的长度——
## 卡池里删掉一张旧卡时，列表长度会大于分母，显示成 19/18 就难看了。
## keep 是「这条算不算数」：变身第二形态不进图鉴，分母里也就不能有它，
## 否则「遇见过的敌人」永远差一只，玩家看着就是没集齐。
func _discovered_text(database: Dictionary, is_known: Callable, keep: Callable = Callable()) -> String:
	var found := 0
	var total := 0
	for entry: Variant in database.values():
		if keep.is_valid() and not keep.call(entry):
			continue
		total += 1
		if is_known.call(entry):
			found += 1
	return "%d / %d" % [found, total]


func _make_stat_row(name_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", VALUE_COLOR)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value_label)

	return row


# --- 角色进度 ---

## 所有角色都摆出来，一局没打过的显示 0——后续加角色不用改这里。
func _add_character_rows() -> void:
	var mp := GameManager.meta_progress
	for character: PlayerData in DataManager.characters_in_order():
		var wins := 0
		var losses := 0
		var best := 0
		if mp != null:
			wins = mp.stat_int(character.character_id, "wins")
			losses = mp.stat_int(character.character_id, "deaths")
			best = mp.stat_int(character.character_id, "best_floor")
		add_row(character.character_name, "胜 %d / 负 %d ・ 最高 %d 层" % [wins, losses, best])


# --- 成就 ---

func _add_achievements() -> void:
	var list := _sorted_achievements()
	var unlocked := 0
	var mp := GameManager.meta_progress
	if mp != null:
		for achievement: Achievement in list:
			if mp.has_achievement(achievement.achievement_id):
				unlocked += 1

	_add_header("成就", "%d / %d" % [unlocked, list.size()])

	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 14)
	_flow.add_theme_constant_override("v_separation", 18)
	add_content(_flow)

	if list.is_empty():
		var empty := Label.new()
		empty.text = "暂无成就"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", MUTED)
		_flow.add_child(empty)
		return

	for achievement: Achievement in list:
		_flow.add_child(_make_achievement_entry(achievement, mp))


## 按条件再按阈值排，同一类的成就挨在一起（首战告捷 / 尖塔常客、出师未捷 / 屡败屡战）。
## 直接遍历 achievement_database 出来的是字典哈希序，看着是乱的。
func _sorted_achievements() -> Array[Achievement]:
	var list: Array[Achievement] = []
	for achievement: Achievement in DataManager.achievement_database.values():
		list.append(achievement)
	list.sort_custom(func(a: Achievement, b: Achievement) -> bool:
		if a.condition != b.condition:
			return a.condition < b.condition
		if a.threshold != b.threshold:
			return a.threshold < b.threshold
		return a.display_name < b.display_name)
	return list


## 成就不像百科要藏内容：上锁的照样显示名字，只把图标换成挂锁。
func _make_achievement_entry(achievement: Achievement, mp: MetaProgress) -> Control:
	var unlocked := mp != null and mp.has_achievement(achievement.achievement_id)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SLOT_SIZE, 0)
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.tooltip_text = achievement.description

	var name_text := achievement.display_name
	var letter := name_text.substr(0, 1) if not name_text.is_empty() else "?"
	column.add_child(CodexIcon.make_slot(ArtIcons.load_or_null(achievement.get_icon_path()),
		letter, VALUE_COLOR if unlocked else LOCKED_COLOR, unlocked, SLOT_SIZE))

	var name_label := Label.new()
	name_label.text = name_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", NAME_COLOR if unlocked else MUTED)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	return column


# --- 排版小工具 ---

func _add_header(text: String, counter: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	row.add_child(header)

	if not counter.is_empty():
		var counter_label := Label.new()
		counter_label.text = counter
		counter_label.add_theme_font_size_override("font_size", 15)
		counter_label.add_theme_color_override("font_color", MUTED)
		counter_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		row.add_child(counter_label)

	add_content(row)


func _make_gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## 秒数格式化成「N时N分N秒」，不足一小时就不显示「时」。
func _format_duration(seconds: int) -> String:
	if seconds <= 0:
		return "0秒"
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	var secs := seconds % 60
	if hours > 0:
		return "%d时%d分%d秒" % [hours, minutes, secs]
	if minutes > 0:
		return "%d分%d秒" % [minutes, secs]
	return "%d秒" % secs
