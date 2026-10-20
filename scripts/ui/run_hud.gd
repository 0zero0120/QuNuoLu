class_name RunHud
extends CanvasLayer

## 全局横条：「这一局的」信息都收在这里——血量 / 金币 / 层数 / 药水 / 遗物，
## 外加右上角那排按钮（卡组 · 地图 · 设置）。
##
## 它和战斗、地图、商店、休息、事件那些界面是**分开的两层**：横条全局只有这一份，
## 建在 GameManager 身上（autoload 挂在 /root 下，换屏带不走它），
## 各个界面里原来各摆一份的那几个标签都删掉了。
##
## 作用域也分得清：横条上的「卡组」看的是**这一局整副牌组**；
## 战斗页左下角右下角的抽牌堆 / 弃牌堆才是「当局的」——那里抽牌弃牌不会动到横条上这个。
##
## 显不显示跟着 GameManager.current_screen 走：每帧看一眼，跟上次不一样才切换。
## 用轮询而不是信号，是因为 current_screen 有二十来处直接赋值（含测试），钩不住；
## MusicManager 早就在用同一套办法。

const LAYER: int = 95
## 弹窗层：牌组 / 设置 / 药水确认都挂在这一层上。
## 挂这儿而不是散在各场景里有两个原因：一是横条的子节点不再随场景销毁，
## 换屏时必须靠 close_modals() 主动收，收在这一处就够；二是牌组查看器以前挂在场景根节点上
## （第 0 层），会被这条横条盖住，挂到 96 才正常。
const MODAL_LAYER: int = 96

const BAR_HEIGHT: float = 56.0
## 遗物排贴着横条下沿挂（56 = BAR_HEIGHT），高度顶到 y=94 为止。
## **94 是硬上限**：横条是 CanvasLayer 95，画在所有界面之上，而横条底下各屏的正文就从 94 起
## （地图的 MapScrollContainer / LegendPanel 都是 offset_top = 94，商店标题 96、奖励页标题 102）。
## 再往下这排就会压住地图那屏的图例面板上边框。
const RELIC_ROW_TOP: float = 56.0
const RELIC_ROW_HEIGHT: float = 38.0
const POTION_SIZE := Vector2(44, 44)
const BUTTON_SIZE := Vector2(84, 32)

const BAR_COLOR := Color(0.08, 0.08, 0.13, 0.94)
const TEXT_COLOR := Color(0.90, 0.90, 0.94)
const HP_COLOR := Color(0.88, 0.36, 0.36)
const GOLD_COLOR := Color(0.95, 0.82, 0.45)
const FLOOR_COLOR := Color(0.78, 0.80, 0.90)
const TIME_COLOR := Color(0.62, 0.60, 0.70)

var _root: Control
var _name_label: Label
var _hp_label: Label
var _gold_label: Label
var _floor_label: Label
var _time_label: Label
var _potion_bar: HBoxContainer
var _relic_row: HBoxContainer
var _modal_canvas: CanvasLayer

var _hp_current: int = 0
var _hp_max: int = 0
var _last_screen: int = -1
var _last_battle: BattleManager = null
var _pending_potion_slot: int = -1
## 药水槽这一回合允不允许点。归战斗那边的回合状态机管：敌人回合关掉，回到玩家回合再开。
var _potions_active: bool = true
## 开设置之前整棵树是不是已经停着了（比如正压着地图浮层）。关掉时要还原成原样。
var _paused_before_modal: bool = false


func _ready() -> void:
	layer = LAYER
	# ALWAYS：暂停中（比如压着地图浮层）横条上的按钮照样点得着。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_connect_signals()
	_sync_hp()
	_last_screen = int(GameManager.current_screen)
	_root.visible = GameManager.is_in_run_screen()
	refresh()


func _process(_delta: float) -> void:
	var screen := int(GameManager.current_screen)
	var battle := GameManager.active_battle
	if screen == _last_screen and battle == _last_battle:
		if _root.visible:
			_refresh_time()
		return
	_last_screen = screen
	_last_battle = battle
	# 换屏和「战斗开打 / 打完」都要重新对一遍：药水槽能不能点看的就是有没有活着的战斗，
	# 而 current_screen 变成 BATTLE 的那一刻战斗场景还没装上，active_battle 还是空的。
	_sync_hp()
	_root.visible = GameManager.is_in_run_screen()
	refresh()


# --- 组装 ---

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 铺满视口。这里没有容器替它撑尺寸：子节点挂的是 1.0 / 0.5 这类锚点，
	# 根节点自己不铺满的话它们全按 0×0 算——通宽横条宽度会变成 0，
	# 贴右边缘那排按钮会跑到屏幕外（锚在 1.0，偏移 -440，结果落在负坐标上）。
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	var bar := ColorRect.new()
	bar.name = "Bar"
	bar.color = BAR_COLOR
	# 底下的界面要能继续收到点击：这条通宽横条只是「画」在那儿，不挡鼠标。
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_right = 1.0
	bar.offset_bottom = BAR_HEIGHT
	_root.add_child(bar)

	_build_left_group()
	_build_floor_label()
	_build_right_group()
	_build_relic_row()

	_modal_canvas = CanvasLayer.new()
	_modal_canvas.name = "ModalCanvas"
	_modal_canvas.layer = MODAL_LAYER
	_modal_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_modal_canvas)


## 左组：名字 · 血量 · 金币 · 药水槽。三种对齐（左/中/右）一个 HBox 装不下，
## 所以是三个兄弟节点各自锚定，不是一个容器分列。
## 这三组的高度都锁在横条里（锚上下都是 0.0，靠 offsets 定高）：整屏那么高的话，
## 里面 SIZE_SHRINK_CENTER 的东西会被摆到屏幕正中间去，而不是横条那一行。
func _build_left_group() -> void:
	var left := HBoxContainer.new()
	left.name = "LeftGroup"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.offset_left = 16.0
	left.offset_right = 700.0
	left.offset_top = 6.0
	left.offset_bottom = BAR_HEIGHT - 6.0
	left.add_theme_constant_override("separation", 18)
	_root.add_child(left)

	_name_label = _make_label("", 17, TEXT_COLOR)
	left.add_child(_name_label)
	_hp_label = _make_label("", 17, HP_COLOR)
	left.add_child(_hp_label)
	_gold_label = _make_label("", 17, GOLD_COLOR)
	left.add_child(_gold_label)

	_potion_bar = HBoxContainer.new()
	_potion_bar.name = "PotionBar"
	_potion_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potion_bar.add_theme_constant_override("separation", 6)
	_potion_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(_potion_bar)


func _build_floor_label() -> void:
	_floor_label = _make_label("", 18, FLOOR_COLOR)
	_floor_label.name = "FloorLabel"
	_floor_label.anchor_left = 0.5
	_floor_label.anchor_right = 0.5
	_floor_label.offset_left = -140.0
	_floor_label.offset_right = 140.0
	_floor_label.offset_top = 0.0
	_floor_label.offset_bottom = BAR_HEIGHT
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_floor_label)


## 右组：计时器 · 卡组 · 地图 · 设置。整组贴右边缘，内容靠 END 对齐。
func _build_right_group() -> void:
	var right := HBoxContainer.new()
	right.name = "RightGroup"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -440.0
	right.offset_right = -16.0
	right.offset_top = 6.0
	right.offset_bottom = BAR_HEIGHT - 6.0
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 10)
	_root.add_child(right)

	_time_label = _make_label("", 17, TIME_COLOR)
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_time_label)
	_add_button(right, "卡组", _on_deck_pressed)
	_add_button(right, "地图", _on_map_pressed)
	_add_button(right, "设置", _on_settings_pressed)


func _build_relic_row() -> void:
	_relic_row = HBoxContainer.new()
	_relic_row.name = "RelicRow"
	_relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relic_row.anchor_right = 1.0
	_relic_row.offset_left = 16.0
	_relic_row.offset_top = RELIC_ROW_TOP
	_relic_row.offset_bottom = RELIC_ROW_TOP + RELIC_ROW_HEIGHT
	_relic_row.add_theme_constant_override("separation", 8)
	_root.add_child(_relic_row)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_button(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 16)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 不给方向键选中：地图那页方向键是「选下一个节点」，战斗里是手牌相关的，
	# 焦点被右上角这一排抢走很别扭。
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _connect_signals() -> void:
	EventBus.player_hp_changed.connect(_on_player_hp_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.relic_obtained.connect(_on_relic_obtained)
	EventBus.relic_charges_changed.connect(_on_relic_charges_changed)
	EventBus.potion_obtained.connect(_on_potion_changed)
	EventBus.potion_used.connect(_on_potion_used)


# --- 刷新 ---

## 重刷横条上所有数字。战斗之外改了状态的地方（休息站治愈、事件页扣血）走
## GameManager.set_player_hp，那条路自己会发信号；这里给的是「换屏之后对一遍」的兜底。
func refresh() -> void:
	if not _root.visible:
		return
	_refresh_name()
	_refresh_hp()
	_refresh_gold()
	_refresh_floor()
	_refresh_potions()
	_refresh_relics()
	_refresh_time()


## 血量有两个来源：战斗里听 player_hp_changed（Player 节点发的是实时值，
## 而 player_data.current_hp 要到战斗结束才同步回去），战斗之外直接读 player_data。
func _sync_hp() -> void:
	var bm := GameManager.active_battle
	if bm != null and is_instance_valid(bm):
		return
	if GameManager.player_data == null:
		return
	_hp_current = GameManager.player_data.current_hp
	_hp_max = GameManager.player_data.max_hp


func _refresh_name() -> void:
	if GameManager.player_data == null:
		_name_label.text = ""
		return
	_name_label.text = GameManager.player_data.character_name


func _refresh_hp() -> void:
	_hp_label.text = "❤ %d/%d" % [_hp_current, _hp_max]


func _refresh_gold() -> void:
	_gold_label.text = "💰 %d" % GameManager.current_gold


## 层数是全局编号（第 2 章从 17 层起），和商店涨价、爬塔成就、历史记录同一套口径；
## 章号另标一个，玩家才知道自己爬了多深、还剩几章。
func _refresh_floor() -> void:
	_floor_label.text = "第 %d 章 · 第 %d 层" % [GameManager.current_chapter, GameManager.current_floor]


func _refresh_time() -> void:
	var total: int = maxi(0, GameManager.run_elapsed_seconds)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	_time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]


func _refresh_potions() -> void:
	for child in _potion_bar.get_children():
		_potion_bar.remove_child(child)
		child.queue_free()
	var slots := GameManager.get_potion_slots()
	var button_scene := load("res://scenes/ui/potion_button.tscn") as PackedScene
	for i in range(slots.size()):
		var button := button_scene.instantiate() as PotionButton
		button.custom_minimum_size = POTION_SIZE
		button.setup(i, slots[i])
		button.potion_clicked.connect(_on_potion_clicked)
		_potion_bar.add_child(button)
	_apply_potions_active()


func _refresh_relics() -> void:
	for child in _relic_row.get_children():
		_relic_row.remove_child(child)
		child.queue_free()
	for relic in GameManager.current_relics:
		_relic_row.add_child(_make_relic_panel(relic))


func _make_relic_panel(relic: RelicData) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(38, 38)
	panel.tooltip_text = "%s\n%s" % [relic.relic_name, relic.description]
	if relic.max_charges > 0:
		# 有限次的遗物得让玩家看得见还剩几次——不然它静悄悄地不再触发，
		# 玩家只会以为遗物坏了。
		panel.tooltip_text += "\n（剩余 %d 次）" % GameManager.get_relic_charges(relic.relic_id)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := ArtIcons.load_or_null(relic.get_icon_path())
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.anchors_preset = Control.PRESET_FULL_RECT
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		panel.add_child(icon)
		return panel
	# 没图才退回那颗菱形占位。这个尺寸的槽里，有没有图远不如「东西够不够大」重要。
	var fallback := Label.new()
	fallback.text = "🔹"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.anchors_preset = Control.PRESET_FULL_RECT
	fallback.anchor_right = 1.0
	fallback.anchor_bottom = 1.0
	fallback.add_theme_font_size_override("font_size", 26)
	panel.add_child(fallback)
	return panel


# --- 信号 ---

func _on_player_hp_changed(current: int, maximum: int) -> void:
	_hp_current = current
	_hp_max = maximum
	if _root.visible:
		_refresh_hp()


func _on_gold_changed(_amount: int) -> void:
	if _root.visible:
		_refresh_gold()


## 遗物那排得跟着重建。战斗页从前只在 _ready() 里建一次，战斗中途拿到的遗物当场不显示，
## 地图 / 商店 / 事件页更是完全看不到遗物——那正是它该进这条全局层的原因。
func _on_relic_obtained(_relic: RelicData) -> void:
	if _root.visible:
		_refresh_relics()


## 充能掉了一档：整排重画。面板是每次重建的、tooltip 是建的时候拼好的字符串，
## 不重建的话 tooltip 里那个「剩余 N 次」会一直停在拿到手时的数。
func _on_relic_charges_changed(_relic_id: String, _remaining: int) -> void:
	if _root.visible:
		_refresh_relics()


func _on_potion_changed(_potion: PotionData) -> void:
	if _root.visible:
		_refresh_potions()


func _on_potion_used(_potion: PotionData, _slot: int) -> void:
	if _root.visible:
		_refresh_potions()


# --- 药水 ---

## 药水槽要不要「能点」。两道关：这一回合允许（敌人回合关掉），
## 而且现在真有一场活着的战斗——PotionManager 在没有战斗上下文时只认得
## 回血 / 加力量 / 加敏捷 / 加金币，能量、格挡、群伤那几种会被白白消耗掉、什么都不发生。
func _potions_usable() -> bool:
	if not _potions_active:
		return false
	var bm := GameManager.active_battle
	return bm != null and is_instance_valid(bm)


func _apply_potions_active() -> void:
	var usable := _potions_usable()
	for child in _potion_bar.get_children():
		if child is PotionButton:
			(child as PotionButton).set_active(usable)


## 回合状态机调它：敌人回合关掉，回到玩家回合再开。BattleManager 那边只做转发。
func set_potions_active(active: bool) -> void:
	_potions_active = active
	_apply_potions_active()


func _potion_at(slot_index: int) -> PotionData:
	var slots := GameManager.get_potion_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return null
	return slots[slot_index] as PotionData


func _on_potion_clicked(slot_index: int) -> void:
	if not _potions_usable():
		return
	var bm := GameManager.active_battle
	if bm.state_machine == null or bm.state_machine.get_current_state_name() != "PlayerTurn":
		return
	var potion := _potion_at(slot_index)
	if potion == null:
		return
	# 再点一次正在等目标的那瓶＝取消，和「点已选中的手牌＝取消选中」是同一个手感。
	if potion.is_targeted and bm.pending_potion_slot == slot_index:
		bm.pending_potion_slot = -1
		return
	# 所有药水都先弹确认框，指向性的也一样：那个框里有名字、图、效果说明，
	# 也正是玩家点下去之后该看到的东西。确认之后指针向性的才进选目标态。
	# 打开另一瓶之前先把旧的目标态收掉，否则确认完这瓶，下次点敌人会把旧那瓶也顺手喝掉。
	bm.pending_potion_slot = -1
	_pending_potion_slot = slot_index
	_show_potion_confirm()


func _show_potion_confirm() -> void:
	_hide_potion_confirm()
	var potion := _potion_at(_pending_potion_slot)
	if potion == null:
		_pending_potion_slot = -1
		return
	var scene := load("res://scenes/ui/potion_confirm.tscn") as PackedScene
	var confirm := scene.instantiate() as PotionConfirm
	confirm.confirmed.connect(_on_potion_confirm)
	confirm.cancelled.connect(_on_potion_cancel)
	_modal_canvas.add_child(confirm)
	# 进树之后才 setup：框里那几个 @onready 节点要等 _ready 跑完才有值。
	confirm.setup(potion)


func _hide_potion_confirm() -> void:
	for child in _modal_canvas.get_children():
		if child is PotionConfirm:
			_modal_canvas.remove_child(child)
			child.queue_free()


func _on_potion_confirm() -> void:
	_hide_potion_confirm()
	var slot := _pending_potion_slot
	_pending_potion_slot = -1
	var bm := GameManager.active_battle
	if bm == null or not is_instance_valid(bm):
		return
	# 确认框开着的时候也许回合已经翻过去了（比如键盘走了别的路）：不在玩家回合就什么都不做，
	# 药水原封不动留在槽里。
	if bm.state_machine == null or bm.state_machine.get_current_state_name() != "PlayerTurn":
		return
	var potion := _potion_at(slot)
	# 指向性药水确认的是「要用它」，不是「往谁身上用」：框关掉之后进选目标态。
	if potion != null and potion.is_targeted:
		bm.pending_potion_slot = slot
		return
	# PotionManager 拿到 bm 就自己会把玩家状态和战斗结束都重算一遍，这里只管横条上的数字。
	if GameManager.use_potion(slot, bm):
		_refresh_gold()
		_refresh_potions()


func _on_potion_cancel() -> void:
	_hide_potion_confirm()
	_pending_potion_slot = -1


# --- 三个按钮 ---

func _on_deck_pressed() -> void:
	open_deck_view()


func _on_map_pressed() -> void:
	GameManager.open_map_view()


func _on_settings_pressed() -> void:
	open_settings()


# --- 弹窗 ---

func _has_modal() -> bool:
	return _modal_canvas.get_child_count() > 0


## 看这一局整副牌组。返回「这次有没有真打开」，没打开就别吃掉那次按键。
func open_deck_view() -> bool:
	return open_card_view(GameManager.current_deck, "牌组")


## 牌组和战斗里那三个牌堆都走这里，省得各写一份。
## 一律挂 MODAL_LAYER，不挂各场景的根节点：根节点是第 0 层，会被这条横条盖住，
## 而查看器的关闭按钮正好落在右上角、和横条那排按钮重叠——点下去开的是「设置」，
## 设置一开整棵树就暂停，查看器不是 ALWAYS，连 ESC 都收不到，人就锁死在里面了。
## 返回「这次有没有真打开」，没打开就别吃掉那次按键。
func open_card_view(cards: Array[CardData], title: String) -> bool:
	if _has_modal():
		return false
	var deck_view: DeckView = load("res://scenes/ui/deck_view.tscn").instantiate() as DeckView
	deck_view.setup(cards, title)
	_modal_canvas.add_child(deck_view)
	return true


## 就地盖一层设置面板。树暂停，底下那个界面冻住；关掉时还原成**开之前**的样子——
## 从地图浮层里开设置（那时树本来就停着），关掉之后地图还得停着。
func open_settings() -> void:
	if _has_modal():
		return
	var screen := SettingsScreen.new()
	screen.setup(SettingsScreen.TAB_GAME)
	screen.closed.connect(_on_settings_closed)
	_paused_before_modal = get_tree().paused
	_modal_canvas.add_child(screen)
	get_tree().paused = true


func _on_settings_closed() -> void:
	if not _paused_before_modal:
		get_tree().paused = false
	_paused_before_modal = false


## 换屏时收掉所有弹窗。横条的子节点不随场景销毁，不收的话
## 「战斗中开设置 → 回主菜单」会把一个暂停着的设置页留在主菜单上面。
func close_modals() -> void:
	for child in _modal_canvas.get_children():
		_modal_canvas.remove_child(child)
		child.queue_free()
	_pending_potion_slot = -1
	_paused_before_modal = false
