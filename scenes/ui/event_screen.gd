class_name EventScreen
extends Control

@onready var title_label: Label = %TitleLabel
@onready var desc_label: Label = %DescLabel
@onready var option_container: VBoxContainer = %OptionContainer
@onready var event_art: TextureRect = %EventArt

## 事件插画目录。文件名就是 event_id，跟 resources/events/*.tres 一一对应。
const EVENT_ART_DIR := "res://assets/art/ui/events/"

## 选项提示文案。测试拿它当动作白名单：.tres 里 action 拼错一个字母，
## 这里取不到对应文案，断言就会报红。新增动作必须同时补进来。
const ACTION_TOOLTIPS: Dictionary = {
	"nothing": "什么也不做",
	"gain_gold": "获得 %d 金币",
	"buy_potion": "花费 %d 金币，随机获得一瓶药水",
	"gain_potion": "随机获得一瓶药水",
	"gain_strength": "永久获得 %d 点力量",
	"heal_percent": "恢复最大生命值的 %d%%",
	"heal_full": "恢复全部生命",
	"lose_hp": "失去 %d 点生命",
	"gain_max_hp": "生命上限提高 %d",
	"gain_relic": "随机获得一件遗物",
	"remove_card": "从牌组中移除一张卡牌",
	"upgrade_card": "升级一张卡牌",
	"lose_max_hp": "生命上限降低 %d",
}

## 这两个动作要先弹选卡器再落账，走的是另一条路（_open_card_picker）。
const CARD_PICK_ACTIONS: Array[String] = ["remove_card", "upgrade_card"]

## 事件的池子。事件节点抽通用池，诅咒祭坛节点抽祭坛池——同一个界面、同一套动作，
## 只有货源不同，所以分池靠 EventData.pool 这个字段，不另做一个界面。
const POOL_GENERAL := "general"
const POOL_ALTAR := "altar"

## 事件面板是 560×640、居中摆的（见 event_screen.tscn），所以它的上下沿各在屏幕中心往外 320 处。
## 结果提示和「继续」只能摆到面板**外面**那两条空带上——面板里面早被正文和选项占满了。
## 原来那组偏移（提示 -110、按钮 +30）落在面板内部，一个压住正文最后一行、一个压住第一个选项，
## 两行字叠成一团。这里的数是按面板尺寸推出来的，不是试出来的。
const PANEL_HALF_HEIGHT := 320.0
const OVERLAY_GAP := 16.0
const FEEDBACK_HEIGHT := 90.0
const LEAVE_BUTTON_SIZE := Vector2(200.0, 44.0)

func _ready() -> void:
	UIBackground.apply(self, "event")
	# 抽中哪个事件、选了哪个选项都锁进存档：重进还是同一个事件，
	# 已经做过的选择不给换一个重来。
	var state := GameManager.ensure_node_state(_roll_state)
	var evt := _current_event()
	title_label.text = evt.title
	desc_label.text = evt.text
	_apply_event_art(evt)

	# path 是「一路选下来的下标」，一个阶段一个。走到第几页全靠它，所以多阶段事件
	# 退出重进停在原阶段是白拿的——路径本身就是存档。
	var path: Array = state.get("path", [])
	var finished := _is_finished(path)
	_render_options(_options_at(path), not finished)

	# 反馈是一路攒下来的，中途重进也要看得见上一页做过什么。
	var result_text := str(state.get("result_text", ""))
	if not result_text.is_empty():
		_show_feedback(result_text)

	if finished:
		_show_leave_button()

## 抽选走 GameManager.rand_pick（本局的 run_rng），不用全局 randi()——那样种子管不住它，
## 同一个种子两次开局会抽到不同事件，把「同种子可复现」这条既有约定破坏掉。
## path 从空数组起步：一个阶段都还没走，_is_finished 认得出这是「还没开始」。
func _roll_state() -> Dictionary:
	var event_id := ""
	var pool := _event_pool()
	if not pool.is_empty():
		# 一局之内同一个事件不重复：先把本局已经见过的滤掉。全见过了就退回整池——
		# 事件库再小也不能把玩家卡进一个空白节点里。池子是分开的，通用池和祭坛池各滤各的。
		var unseen: Array = []
		for evt: EventData in pool:
			if not GameManager.seen_event_ids.has(evt.event_id):
				unseen.append(evt)
		if not unseen.is_empty():
			pool = unseen
		event_id = (GameManager.rand_pick(pool) as EventData).event_id
		# 当场记账：这个 id 是这一局用掉的，重进这个节点也该还是它（node_state 已经锁死了），
		# 但下一个事件节点必须看得见「这条用过了」。
		GameManager.seen_event_ids.append(event_id)
	return {"event_id": event_id, "path": [], "result_text": ""}

## 这次进的是哪种节点就抽哪个池。祭坛池还没配内容时退回通用池——宁可给个普通事件，
## 也别让玩家推开门看见一片空白。
func _event_pool() -> Array:
	var want := POOL_ALTAR if GameManager.current_encounter_type == MapNodeData.NodeType.ALTAR \
		else POOL_GENERAL
	var pool := _events_in(want)
	if pool.is_empty() and want != POOL_GENERAL:
		pool = _events_in(POOL_GENERAL)
	return pool

func _events_in(pool_name: String) -> Array:
	var out: Array = []
	for evt: EventData in DataManager.event_database.values():
		if evt.pool == pool_name:
			out.append(evt)
	return out

## 按已选路径走到底，得到当前该摆出来的那组选项。下标越界（存档被手改过、事件被删改过）
## 就当走到头：退回空数组，界面会摆成「已结束」的样子，不会崩。
func _options_at(path: Array) -> Array[EventOption]:
	var opts: Array[EventOption] = _current_event().options
	for idx: Variant in path:
		var i := int(idx)
		if i < 0 or i >= opts.size():
			var none: Array[EventOption] = []
			return none
		opts = (opts[i] as EventOption).next_options
	return opts

## 走到头没有：看**实际选的那条路径**末端那一项有没有下一组选项。
## 同一个阶段里，一项可以接着往下、另一项就此收尾，所以只能按走的那条路判，不能按这一页判。
func _is_finished(path: Array) -> bool:
	if path.is_empty():
		return false
	return _options_at(path).is_empty()

## 摆一组选项。index 绑的是**这一页里**的下标，正好就是本阶段的路径分量。
## 换页时先把旧的摘下来再 queue_free：queue_free 要到帧末才生效，光靠它的话
## 新旧两批按钮会同时挂在容器里，容器高度会闪一下，点击也可能落到正要消失的旧按钮上。
func _render_options(opts: Array[EventOption], enabled: bool) -> void:
	for child in option_container.get_children():
		option_container.remove_child(child)
		child.queue_free()
	for i in range(opts.size()):
		var opt: EventOption = opts[i]
		var btn := Button.new()
		btn.text = opt.label
		btn.tooltip_text = _get_option_tooltip(opt)
		btn.custom_minimum_size = Vector2(300, 44)
		btn.add_theme_font_size_override("font_size", 15)
		btn.disabled = not enabled
		if enabled:
			btn.pressed.connect(_on_option_chosen.bind(i, opt))
		option_container.add_child(btn)

## 事件插画。取不到就整块隐藏——不留一个空框（与 card.gd._update_art() 缺图隐藏同口径）。
func _apply_event_art(evt: EventData) -> void:
	var tex := UIBackground.load_or_null("events/" + str(evt.event_id))
	event_art.texture = tex
	event_art.visible = tex != null

func _disable_options() -> void:
	for child in option_container.get_children():
		if child is Button:
			(child as Button).disabled = true

## 抽到的那份 .tres 被删掉时回落到一个写死在代码里的事件。不能回退到「池子里的第 0 个」——
## 池子一扩充，第 0 个随时会变成另一个事件，读旧档会看到完全不相干的内容。
func _current_event() -> EventData:
	var evt := DataManager.get_event(str(GameManager.node_state.get("event_id", "")))
	return evt if evt else _fallback_event()

func _fallback_event() -> EventData:
	var evt := EventData.new()
	evt.event_id = "fallback"
	evt.title = "空无一物"
	evt.text = "这里空无一物，只有一阵穿堂风。"
	var leave := EventOption.new()
	leave.label = "离开"
	leave.action = "nothing"
	var opts: Array[EventOption] = [leave]
	evt.options = opts
	return evt

func _get_option_tooltip(opt: EventOption) -> String:
	var template := str(ACTION_TOOLTIPS.get(opt.action, ""))
	var body := ""
	if not template.is_empty():
		if not template.contains("%d"):
			body = template
		elif opt.action == "heal_percent":
			body = template % int(opt.value * 100)
		else:
			body = template % int(opt.value)
	# 前置条件摆进提示里：按钮是不变灰的，玩家全靠这句话知道自己差在哪。
	if opt.cost_hp > 0:
		body = _append_hint(body, "代价：%d 点生命" % opt.cost_hp)
	if not opt.require_relic.is_empty():
		body = _append_hint(body, "需要：%s" % _relic_name(opt.require_relic))
	return body

func _append_hint(text: String, hint: String) -> String:
	return hint if text.is_empty() else "%s，%s" % [text, hint]

func _relic_name(relic_id: String) -> String:
	var relic := DataManager.get_relic(relic_id)
	return relic.relic_name if relic else relic_id

## 前置条件不满足时给出一句话，满足时给空串。绕开按钮禁用是有意为之：
## 事件只有一次机会，把选项变灰等于堵死出路——弹句话告诉玩家差在哪，还能改点别的。
## buy_potion 的金币不足也归到这里，免得同一个「买不起」在两条路上有两种表现。
func _blocked_reason(opt: EventOption) -> String:
	var fallback := ""
	if not opt.require_relic.is_empty() and not GameManager.has_relic(opt.require_relic):
		fallback = "你身上没有%s，做不了这件事。" % _relic_name(opt.require_relic)
	elif opt.cost_hp > 0 and GameManager.player_data.current_hp <= opt.cost_hp:
		fallback = "你的生命值不够，做不了这件事。"
	elif opt.action == "buy_potion" and GameManager.current_gold < int(opt.value):
		fallback = "你的金币不够。"
	elif opt.action == "lose_max_hp" and GameManager.player_data.max_hp <= int(opt.value):
		fallback = "你的生命上限不够，做不了这件事。"
	if fallback.is_empty():
		return ""
	return opt.blocked_text if not opt.blocked_text.is_empty() else fallback

## 要弹选卡器的选项不在这里落账——挑完才走 _apply_option，
## 中途关掉选卡器等于没选过，还能改选另一个。
## 条件不足的同样不落账，而且按钮不禁用，玩家可以接着点。
func _on_option_chosen(index: int, opt: EventOption) -> void:
	var blocked := _blocked_reason(opt)
	if not blocked.is_empty():
		_show_feedback(blocked)
		return
	if opt.action in CARD_PICK_ACTIONS:
		_open_card_picker(index, opt)
		return
	_apply_option(index, opt, null)

func _open_card_picker(index: int, opt: EventOption) -> void:
	var candidates := _candidates_for(opt.action)
	if candidates.is_empty():
		_apply_option(index, opt, null)
		return
	var picker_scene := load("res://scenes/ui/card_picker_screen.tscn") as PackedScene
	if picker_scene == null:
		return
	var picker := picker_scene.instantiate() as CardPickerScreen
	picker.setup(candidates, "选择一张卡牌移除" if opt.action == "remove_card"
		else "选择一张卡牌升级")
	picker.card_chosen.connect(_on_card_picked.bind(index, opt))
	add_child(picker)

func _candidates_for(action: String) -> Array[CardData]:
	var out: Array[CardData] = []
	if action == "upgrade_card":
		for card: CardData in GameManager.current_deck:
			if not card.upgraded:
				out.append(card)
		return out
	# 移除：留一张兜底，不给玩家把牌组删空。
	if GameManager.current_deck.size() <= 1:
		return out
	for card: CardData in GameManager.current_deck:
		out.append(card)
	return out

func _on_card_picked(card: CardData, index: int, opt: EventOption) -> void:
	# 升级类选项留一份升级前的牌，落账后再把「升级前 / 升级后」摆给玩家看。
	# 另外两种卡牌选项（移除）不需要——移走了就没有「后」可看。
	var before: CardData = null
	if opt.action == "upgrade_card" and not card.upgraded:
		before = card.duplicate() as CardData
	_apply_option(index, opt, card)
	if before != null and card.upgraded:
		CardUpgradePreview.show_for(self, before, card)

## picked 只有选卡类的动作才带得进来。挑中那张卡在这一刻才真动牌组。
## 效果落完才决定是换页还是收尾：中间任何一步出错，牌组和金币也已经改过了，
## 不如先把这一步的账记下来，让玩家看得见自己选了什么。
func _apply_option(index: int, opt: EventOption, picked: CardData) -> void:
	var feedback_msg := _perform(opt, picked)

	# 反馈是一路攒下来的：多阶段事件走到第二页时，第一页做过什么还得看得见。
	var accrued := str(GameManager.node_state.get("result_text", ""))
	var combined := feedback_msg
	if not accrued.is_empty() and not feedback_msg.is_empty():
		combined = "%s\n%s" % [accrued, feedback_msg]

	var path: Array = GameManager.node_state.get("path", [])
	path.append(index)

	# 按下选项就落盘：这次选择带来的金币/药水/力量是既成事实，走到哪一页也是。
	GameManager.node_state["path"] = path
	GameManager.node_state["result_text"] = combined
	GameManager.save_run()

	if not feedback_msg.is_empty():
		_show_feedback(feedback_msg)

	if _is_finished(path):
		_disable_options()
		_show_leave_button()
		return
	# 这一项背后还有下一组选项：接着摆出来。上一批按钮已经摘掉了，不会和新的抢点击。
	_render_options(_options_at(path), true)

## 一个选项的净效果：先付代价（如果有），再落到 action 上，两句话拼成一条反馈，
## 读起来是「失去 6 点生命，力量 +2」。
func _perform(opt: EventOption, picked: CardData) -> String:
	var cost_text := _pay_cost(opt)
	var reward_text := _perform_action(opt, picked)
	if cost_text.is_empty():
		return reward_text
	if reward_text.is_empty():
		return cost_text
	return "%s，%s" % [cost_text, reward_text]

## 代价先落账：血扣了就是扣了，哪怕下面那条 action 落空（比如遗物池空了）也不退。
func _pay_cost(opt: EventOption) -> String:
	if opt.cost_hp <= 0:
		return ""
	# 和 lose_hp 一样扣到 1 点停手。_blocked_reason 已经挡掉了付不起的情况，
	# 这里只是兜底，不让一个选项把人扣死。
	var remaining := maxi(1, GameManager.player_data.current_hp - opt.cost_hp)
	var paid := GameManager.player_data.current_hp - remaining
	GameManager.set_player_hp(remaining)
	return "失去 %d 点生命" % paid

func _perform_action(opt: EventOption, picked: CardData) -> String:
	var amount := int(opt.value)
	match opt.action:
		"gain_gold":
			GameManager.add_gold(amount)
			return "+%d 金币" % amount
		"gain_strength":
			GameManager.player_data.strength += amount
			return "力量 +%d" % amount
		"heal_percent":
			var heal := int(GameManager.player_data.max_hp * opt.value)
			# 走 GameManager.set_player_hp，全局横条上那行血量才跟着动。
			GameManager.set_player_hp(GameManager.player_data.current_hp + heal)
			return "恢复了 %d 点生命" % heal
		"heal_full":
			GameManager.set_player_hp(GameManager.player_data.max_hp)
			return "生命已回满"
		"lose_hp":
			# 事件不该把人打死：扣到 1 点就停手，这也是它和战斗伤害的区别。
			var remaining := maxi(1, GameManager.player_data.current_hp - amount)
			var lost := GameManager.player_data.current_hp - remaining
			GameManager.set_player_hp(remaining)
			return "失去了 %d 点生命" % lost
		"gain_max_hp":
			GameManager.player_data.max_hp += amount
			GameManager.set_player_hp(GameManager.player_data.current_hp + amount)
			return "生命上限 +%d" % amount
		"lose_max_hp":
			# 上限先降，再把当前血量钳下来——反过来的话 current_hp 会有一瞬间超过上限。
			# 至少留 1 点上限：祭坛拿命换东西，但不该把人换成一具空壳。
			# _blocked_reason 已经挡掉了上限不够的情况，这里只是兜底。
			var new_max := maxi(1, GameManager.player_data.max_hp - amount)
			var lost_max := GameManager.player_data.max_hp - new_max
			GameManager.player_data.max_hp = new_max
			GameManager.set_player_hp(mini(GameManager.player_data.current_hp, new_max))
			return "生命上限 -%d" % lost_max
		"buy_potion":
			if GameManager.spend_gold(amount):
				return _grant_random_potion()
			return "金币不足..."
		"gain_potion":
			return _grant_random_potion()
		"gain_relic":
			var relic := DataManager.get_random_obtainable_relic()
			if relic == null:
				return "没能找到什么有用的东西。"
			GameManager.add_relic(relic)
			return "获得了%s！" % relic.relic_name
		"remove_card":
			if picked == null:
				return "牌组已没有可以移除的卡牌。"
			GameManager.remove_card_from_deck(picked)
			return "移除了「%s」" % picked.card_name
		"upgrade_card":
			if picked == null:
				return "没有可升级的卡牌。"
			# 名字要在 upgrade() 之前留一份：那个方法会给名字补上「+」。
			var name_before := picked.card_name
			if not GameManager.upgrade_card(picked):
				return "没有可升级的卡牌。"
			return "「%s」已升级！" % name_before
	return ""

func _grant_random_potion() -> String:
	var potion := DataManager.get_random_potion()
	if potion == null:
		return "获得了一瓶药水！"
	GameManager.add_potion(potion)
	return "获得了%s！" % potion.potion_name

## 摆在面板上沿往上 OVERLAY_GAP 的地方。宽度跟面板齐平（560）：条件不足那几句话比
## 「+40 金币」长得多，窄了会折成好几行。再往上就顶到全局横条 RunHud 了，所以只能贴着面板放。
func _show_feedback(msg: String) -> void:
	var top := -(PANEL_HALF_HEIGHT + OVERLAY_GAP + FEEDBACK_HEIGHT)
	ScreenFeedback.show_message(self, msg, Rect2(-280.0, top, 560.0, FEEDBACK_HEIGHT))

## 摆在面板下沿往下 OVERLAY_GAP 的地方。面板下半截是选项列表，往下是唯一不压东西的方向。
func _show_leave_button() -> void:
	var btn := Button.new()
	btn.text = "继续"
	btn.custom_minimum_size = LEAVE_BUTTON_SIZE
	btn.add_theme_font_size_override("font_size", 16)
	btn.anchors_preset = PRESET_CENTER
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = -LEAVE_BUTTON_SIZE.x * 0.5
	btn.offset_top = PANEL_HALF_HEIGHT + OVERLAY_GAP
	btn.offset_right = LEAVE_BUTTON_SIZE.x * 0.5
	btn.offset_bottom = PANEL_HALF_HEIGHT + OVERLAY_GAP + LEAVE_BUTTON_SIZE.y
	btn.name = "LeaveButton"
	btn.pressed.connect(_on_leave_pressed)
	add_child(btn)

func _on_leave_pressed() -> void:
	GameManager.finish_node()
