extends Node

enum GameScreen {
	MAIN_MENU,
	CHARACTER_SELECT,
	MAP,
	BATTLE,
	SHOP,
	REST,
	REWARD,
	EVENT,
	GAME_OVER,
	VICTORY,
	RELIC_PICK
}

var current_screen: GameScreen = GameScreen.MAIN_MENU
var player_data: PlayerData
## 本局打到第几章，1..CHAPTER_COUNT。章号不拿层数现推——测试和读档都会单独拨 current_floor，
## 一推就会把「打到第 17 层」当成「第 2 章」。
var current_chapter: int = 1
## 全局层数，一路涨到底：第 1 章 0~16、第 2 章 17~33、第 3 章 34~50。
## 商店按层涨价、敌人成群规模、爬塔成就、历史记录全按它算，所以章间不重置。
var current_floor: int = 0
var current_encounter_type: MapNodeData.NodeType = MapNodeData.NodeType.BATTLE
var current_deck: Array[CardData] = []
var current_relics: Array[RelicData] = []
var current_gold: int = 0
var visited_node_ids: Array[String] = []
## 本局已经走进过的事件 id。抽事件时先把它滤掉，一局之内同一个事件不再重复触发。
## 和 visited_node_ids 不同，它**不随换章清空**——「一次游戏」指的是整局三章。
## 全部事件都见过之后退回整池抽，不把玩家卡进一个空事件里。
var seen_event_ids: Array[String] = []
var current_potions: Array = []
var potion_manager: PotionManager
var pending_reward: Dictionary = {}
var meta_progress: MetaProgress
var run_history: RunHistory

## 本局计数。start_new_run 和 load_run 都会写这几个字段，退出续玩不归零。
var run_enemies_killed: int = 0
var run_bosses_killed: int = 0
var run_elapsed_seconds: int = 0
var run_ascension: int = 1
## 本局的种子，九位数字。开局定下来、写进存档，填同一串再开一局会得到一模一样的地图和掉落。
var run_seed: int = 0
## 本局专用的随机数发生器。引擎的全局随机源（randi/randf/Array.shuffle/pick_random）
## 指不到自己的发生器上，所以玩法随机一律走这里，用 rand_pick()/rand_shuffle() 代替那两个数组方法。
var run_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _play_accumulator: float = 0.0
var _unflushed_seconds: int = 0

## 读档后应该落在哪个屏。MAP 表示「没有走到一半的界面」，直接回地图。
## 置位在 map_manager.move_player_to_node()（节点类型→屏幕）、end_state 显示奖励页时（REWARD）；
## 商店/休息/事件由各界面走 finish_node() 清回 MAP，战斗结算由 finish_run() 清回 MAP。
## 用屏幕而不是节点类型：奖励页不是地图上的节点，只有屏幕能表达它。
var resume_screen: GameScreen = GameScreen.MAP

## 当前界面的内容快照：商店的货架与已购状态、休息页二选一的结果、事件页抽中的事件与选项、
## 奖励页抽中的三张牌与金币/药水。
## 商店/休息/事件/奖励进界面时就写一份并立刻落盘（内容锁死，重进不再随机），之后每次操作再写一次。
## 战斗不走这套：战斗中途不存盘，磁盘上留着开打前那一份，读档回到战斗开局。
var node_state: Dictionary = {}

const META_SAVE_PATH: String = "user://meta_progress.json"
const PLAY_FLUSH_INTERVAL: float = 15.0
const LEGACY_META_SAVE_PATH: String = "user://meta_progress.tres"
const MAX_ASCENSION: int = 10
## 随机种子的九位取值范围。随机抽的种子一定落在里头，所以不会出现前导零、显示时永远是九位。
const SEED_MIN: int = 100000000
const SEED_MAX: int = 999999999
const SAVE_SLOT_COUNT: int = 3
## 一局几章。每章自己一张地图，只有最后一章的 Boss 才算通关。
const CHAPTER_COUNT: int = 3
const BOSS_SOUL_BONUS: int = 50
const DEFEAT_SOUL_PER_FLOOR: int = 1
var current_save_slot: int = 0
var pending_new_slot: int = 0
var _pause_overlay: PauseOverlay = null
var _pause_canvas: CanvasLayer = null
var _map_view: MapViewOverlay = null
var _history_view: PlayHistoryOverlay = null
var _next_scene: String = ""

## 常驻的全局横条：血量 / 金币 / 层数 / 药水 / 遗物 + 卡组·地图·设置。
## 建在 GameManager 自己身上（autoload 挂在 /root 下），换屏带不走它——
## 这正是它和那些挂在 current_scene 上的浮层（暂停菜单、地图浮层）的区别。
var run_hud: RunHud = null
## 当前活着的那场战斗。药水只在战斗里才有意义，横条靠这个判「有没有战斗上下文」。
var active_battle: BattleManager = null

## 取当前战斗。active_battle 是强引用，战斗场景被 queue_free 之后它可能还指着已释放的节点，
## 所以别直接读字段——遗物效果、敌人召唤、指向性药水都从这里取。
func get_active_battle() -> BattleManager:
	if active_battle != null and is_instance_valid(active_battle):
		return active_battle
	return null

func get_save_path(slot: int) -> String:
	return "user://save_%d.json" % slot

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	player_data = PlayerData.new()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_potion_manager()
	_load_meta_progress()
	_ensure_run_hud()

## 全局横条只建一次，挂在自己身上。_ready 之外别的地方不许再建——
## 「唯一一份」是这条层的全部意义，重建两次就会出现两条横条一起刷。
func _ensure_run_hud() -> void:
	if run_hud != null and is_instance_valid(run_hud):
		return
	run_hud = RunHud.new()
	run_hud.name = "RunHud"
	add_child(run_hud)

func _process(delta: float) -> void:
	_accumulate_play_time(delta)


## ESC 走这里，而不是每帧轮询 Input.is_action_just_pressed：
## 轮询看不见 set_input_as_handled()，弹窗把事件吃掉也拦不住它，会变成「关掉面板的同时顺手把暂停菜单打开」。
## _unhandled_input 是输入链的最后一站（_input → 界面控件 → 快捷键 → _unhandled_key_input → _unhandled_input），
## 弹窗只要在 _input 里吃掉 ESC，这个方法根本不会被调用。
## process_mode 是 ALWAYS，所以暂停中照样收得到，暂停菜单才关得掉。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_try_open_map_view()
		return
	if event.is_action_pressed("view_history"):
		_try_open_play_history()
		return
	if event.is_action_pressed("view_deck"):
		if _try_open_deck_view():
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if not is_in_run_screen():
		return
	toggle_pause()
	get_viewport().set_input_as_handled()

## process_mode 是 ALWAYS，主菜单、暂停、结算页都在跑，所以只在真正在对局里的画面上累计。
const PLAY_COUNTED_SCREENS := [
	GameScreen.MAP,
	GameScreen.BATTLE,
	GameScreen.SHOP,
	GameScreen.REST,
	GameScreen.REWARD,
	GameScreen.EVENT,
]

## 现在这个屏是不是「局内」。全局横条显不显示、上面那几个快捷键响不响应，都以它为准。
func is_in_run_screen() -> bool:
	return current_screen in PLAY_COUNTED_SCREENS

## 读档时把秒表整个接回存档值。只还原 run_elapsed_seconds 不够——它每帧都被
## _accumulate_play_time 拿 _play_accumulator 重算一遍，累加器不从这儿续上，
## 读档后第一帧就把刚还原的时长冲成 0（表现就是「退出再进来计时器归零」）。
## _unflushed_seconds 也得一起续：它是「本局已经记进 meta 的秒数」，漏了这段，
## 后面那段 flush 会把已经算过的时长往 meta 的 play_seconds 里再加一遍。
## unflushed 传负数表示存档里没这一项（改动之前的老档），按「已全部记入」处理。
func restore_run_timer(elapsed: int, unflushed: int) -> void:
	run_elapsed_seconds = elapsed
	_play_accumulator = float(elapsed)
	_unflushed_seconds = unflushed if unflushed >= 0 else elapsed

func get_unflushed_seconds() -> int:
	return _unflushed_seconds

func _accumulate_play_time(delta: float) -> void:
	if not current_screen in PLAY_COUNTED_SCREENS:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if player_data == null or player_data.character_id.is_empty():
		return
	_play_accumulator += delta
	run_elapsed_seconds = int(_play_accumulator)
	if _play_accumulator - float(_unflushed_seconds) < PLAY_FLUSH_INTERVAL:
		return
	_flush_play_seconds()

## 把还没记进 meta 的秒数补上，返回这次补了多少。进度不至于因为崩溃整局丢掉。
func _flush_play_seconds() -> int:
	var pending := int(_play_accumulator) - _unflushed_seconds
	if pending <= 0 or meta_progress == null:
		return 0
	meta_progress.add_stat(player_data.character_id, "play_seconds", pending)
	_unflushed_seconds += pending
	save_meta_progress()
	return pending

func _do_change_scene(path: String) -> void:
	var packed: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		packed = load(path)
	if packed == null:
		push_error("[GameManager] ALL LOAD METHODS FAILED for: %s" % path)
		return

	var tree := get_tree()
	if tree == null:
		return

	var err := tree.change_scene_to_packed(packed)
	if err != OK:
		push_error("[GameManager] change_scene_to_packed FAILED err=%d, trying change_scene_to_file..." % err)
		var err2 := tree.change_scene_to_file(path)
		if err2 != OK:
			push_error("[GameManager] BOTH METHODS FAILED! err=%d, err2=%d" % [err, err2])

func _ensure_potion_manager() -> void:
	if not potion_manager:
		potion_manager = PotionManager.new()

## 暂停菜单开/关。ESC 和地图浮层的「返回」都走这里，两个入口的行为才一致。
func toggle_pause() -> void:
	if current_screen == GameScreen.MAIN_MENU or current_screen == GameScreen.GAME_OVER or current_screen == GameScreen.VICTORY:
		return
	if _pause_overlay and is_instance_valid(_pause_overlay) and _pause_overlay.visible:
		_pause_overlay.close()
		return
	_ensure_pause_overlay()
	if _pause_overlay:
		_pause_overlay.open()

func _ensure_pause_overlay() -> void:
	if _pause_overlay and is_instance_valid(_pause_overlay):
		return
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.current_scene
	if root == null:
		return

	if not is_instance_valid(_pause_canvas):
		_pause_canvas = CanvasLayer.new()
		_pause_canvas.layer = 100
		_pause_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(_pause_canvas)

	var scene: PackedScene = load("res://scenes/ui/pause_overlay.tscn")
	_pause_overlay = scene.instantiate() as PauseOverlay
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_canvas.add_child(_pause_overlay)

## 对局中按 M 看地图。走到这里说明没有浮层开着——浮层开着的时候 M 归它自己吃
## （它的 _input 是输入链第一站，轮不到这个方法），用来关掉自己。
func _try_open_map_view() -> void:
	# 暂停中不响应：那时候屏幕归暂停菜单管，再压一张地图上去只会让「关掉哪个」说不清。
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if current_screen == GameScreen.MAIN_MENU or current_screen == GameScreen.CHARACTER_SELECT \
			or current_screen == GameScreen.GAME_OVER or current_screen == GameScreen.VICTORY:
		return
	# 没有地图状态就当没按过：不占着这次按键，也不凭空造一张图出来。
	if not has_map_state():
		return
	open_map_view()
	get_viewport().set_input_as_handled()

## 打开只读地图。整棵树暂停、底下的界面冻住——地图是「停下来看一眼」，不是又一个操作界面。
## 暂停归这里开也归这里收（close_map_view / change_screen 各一条），浮层自己不碰。
func open_map_view() -> void:
	if _map_view != null and is_instance_valid(_map_view):
		return
	# 已经站在地图页上就不必再压一层只读地图上去——两张一模一样的地图摞着，
	# 「返回」该回到哪一层都说不清。
	if current_screen == GameScreen.MAP:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	_map_view = MapViewOverlay.new()
	tree.current_scene.add_child(_map_view)
	tree.paused = true

## 关掉地图浮层，回到打开之前那个界面。「返回」按钮、ESC、M 三条路都走这里。
func close_map_view() -> void:
	if _map_view != null and is_instance_valid(_map_view):
		_map_view.queue_free()
	_map_view = null
	var tree := get_tree()
	if tree != null:
		tree.paused = false

## 战斗页里那个战报栏。它是战斗场景的一部分、不常驻，所以每次都现找。
func get_battle_play_history() -> PlayHistory:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("PlayHistory") as PlayHistory

## 对局中按 H 看本场战报。只有战斗里才有战报可看——别的界面按 H 就当没按过，
## 不占着这次按键，也不凭空开一张空浮层出来。
func _try_open_play_history() -> void:
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if current_screen != GameScreen.BATTLE:
		return
	var history := get_battle_play_history()
	if history == null or history.records.is_empty():
		return
	open_play_history(history)
	get_viewport().set_input_as_handled()

## 打开战报浮层，看这一场打出去过的全部牌。整棵树暂停、底下的战斗冻住——
## 战报是「停下来看一眼」。暂停归这里开也归这里收（close_play_history / change_screen 各一条），
## 浮层自己不碰。
func open_play_history(history: PlayHistory) -> void:
	if _history_view != null and is_instance_valid(_history_view):
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	_history_view = PlayHistoryOverlay.new()
	_history_view.setup(history.records)
	tree.current_scene.add_child(_history_view)
	tree.paused = true

## 关掉战报浮层，回到打开之前那个界面。「返回」按钮、ESC、H 三条路都走这里。
func close_play_history() -> void:
	if _history_view != null and is_instance_valid(_history_view):
		_history_view.queue_free()
	_history_view = null
	var tree := get_tree()
	if tree != null:
		tree.paused = false

## 对局中按 D 看牌组。看的是**这一局整副牌组**——战斗里抽牌/弃牌/消耗动的是左下角右下角那几堆，
## 不会动到它。所以这个入口归全局，不归战斗页。
## 返回「这次有没有真打开」，没有就别吃掉这次按键。
func _try_open_deck_view() -> bool:
	if not is_in_run_screen():
		return false
	if run_hud == null or not is_instance_valid(run_hud):
		return false
	return run_hud.open_deck_view()

func change_screen(screen: GameScreen, data: Dictionary = {}) -> void:
	var scene_path: String = ""
	match screen:
		GameScreen.MAIN_MENU:
			scene_path = "res://scenes/ui/main_menu.tscn"
		GameScreen.CHARACTER_SELECT:
			scene_path = "res://scenes/ui/character_select.tscn"
		GameScreen.BATTLE:
			scene_path = "res://scenes/battle/battle_scene.tscn"
		GameScreen.MAP:
			scene_path = "res://scenes/map/map_scene.tscn"
		GameScreen.SHOP:
			scene_path = "res://scenes/ui/shop_screen.tscn"
		GameScreen.REST:
			scene_path = "res://scenes/ui/rest_screen.tscn"
		GameScreen.REWARD:
			scene_path = "res://scenes/ui/card_reward_screen.tscn"
		GameScreen.EVENT:
			scene_path = "res://scenes/ui/event_screen.tscn"
		GameScreen.GAME_OVER:
			scene_path = "res://scenes/ui/game_over_screen.tscn"
		GameScreen.VICTORY:
			scene_path = "res://scenes/ui/victory_screen.tscn"
		GameScreen.RELIC_PICK:
			scene_path = "res://scenes/ui/relic_picker_screen.tscn"
		_:
			return

	if _next_scene == scene_path:
		print("[GameManager] change_screen: already pending '%s', skipping" % scene_path)
		return
	_next_scene = scene_path
	current_screen = screen
	# 弹窗挂在常驻的全局层上，不随场景销毁，所以换屏时必须主动收——
	# 否则「战斗中开设置 → 返回主菜单」会把一个暂停着的设置页留在主菜单上面。
	if run_hud != null and is_instance_valid(run_hud):
		run_hud.close_modals()
	_pause_overlay = null
	_pause_canvas = null
	_map_view = null
	_history_view = null
	get_tree().paused = false
	print("[GameManager] change_screen: screen=%d -> %s, scheduling via Timer" % [screen, scene_path])
	var timer := get_tree().create_timer(0.0)
	timer.timeout.connect(func():
		var p := _next_scene
		_next_scene = ""
		if p.is_empty():
			print("[GameManager] Timer fired but path is empty (cancelled/overwritten)")
			return
		_do_change_scene(p)
	)

## 节点类型 → 落在哪个屏。战斗类（普通/精英/BOSS）都进战斗。
## 进节点时算一次存进 resume_screen，读档直接用它，两边不会各写一份 match 而对不上。
func screen_for_node_type(node_type: MapNodeData.NodeType) -> GameScreen:
	match node_type:
		MapNodeData.NodeType.BATTLE, MapNodeData.NodeType.ELITE, MapNodeData.NodeType.BOSS:
			return GameScreen.BATTLE
		MapNodeData.NodeType.SHOP:
			return GameScreen.SHOP
		MapNodeData.NodeType.REST:
			return GameScreen.REST
		# 诅咒祭坛走的是同一个事件界面：换个池子抽事件而已，界面和行为都复用。
		MapNodeData.NodeType.EVENT, MapNodeData.NodeType.ALTAR:
			return GameScreen.EVENT
		MapNodeData.NodeType.CHEST:
			return GameScreen.RELIC_PICK
	return GameScreen.MAP


## 待办的是不是战斗。只有战斗走「中途退出不存盘、重进回开局」；
## 商店/休息/事件/奖励是另一套——内容进界面就锁死、每次操作都实时落盘，所以退出时照常存。
func pending_is_battle() -> bool:
	return resume_screen == GameScreen.BATTLE


## 取当前界面的内容快照；没有就用 make_default 造一份、立刻落盘。
## 这是「进界面就把内容锁死」的落点：抽出来的商品/事件/奖励和玩家已有状态同一时刻进存档。
func ensure_node_state(make_default: Callable) -> Dictionary:
	if node_state.is_empty():
		node_state = make_default.call()
		save_run()
	return node_state


## 走完商店/休息/事件/奖励：清掉待办屏幕和内容快照再落盘，然后回地图。
## 清完再存，「继续游戏」才会把玩家放在地图上——否则读档又被送回这个已经走完的界面。
func finish_node() -> void:
	resume_screen = GameScreen.MAP
	node_state = {}
	save_run()
	change_screen(GameScreen.MAP)


## 这是不是最后一章的 Boss。整局只有这一处判断「通关还是接着往下走」，
## 遗物三选一的去向和 end_state 的兜底都问它，别各写一份章号比较。
func is_final_chapter() -> bool:
	return current_chapter >= CHAPTER_COUNT


## 打完非最终章的 Boss、选完遗物之后翻到下一章。
## 新地图不在这里生成：落到 MAP 屏时 MapUI._ready() 发现「没有地图状态」就现生成一张
## （start_new_run 走的是同一条路），所以这里只管把上一章的东西全部作废。
func advance_chapter() -> void:
	current_chapter = mini(current_chapter + 1, CHAPTER_COUNT)
	# 上一章的地图、界面内容快照、走过的节点全是上一章的，跟旧图一起作废。
	# node_state 必须显式清——它平时只在 move_player_to_node() 里清，不清的话
	# 上一章商店/事件/奖励的快照会漏进新章的第一个节点。
	clear_map_state()
	node_state = {}
	visited_node_ids.clear()
	current_floor = MapConfig.first_floor_of_chapter(current_chapter)
	resume_screen = GameScreen.MAP
	save_run()
	change_screen(GameScreen.MAP)


## ascension 传 -1 表示「没指定，用账号已解锁的最高级」，这是没走选择器的入口（如测试）的行为。
## 传了 0 或正数就一律钳到 1..已解锁最高级：难度是开局选一次就定死的，UI 传来什么都不能越界。
## seed_value 传 0 表示「没指定，随机抽一个九位数」，正数就照用（玩家在角色详情页亲手填的）。
func start_new_run(character_data: PlayerData, slot: int = -1, ascension: int = -1,
		seed_value: int = 0) -> void:
	if slot >= 0:
		current_save_slot = slot
	# 复制一份再改：character_data 是 DataManager 角色库里的共享实例。直接写会把这一局的
	# 血量/金币/力量改到库上，而角色详情页的「金币」读的就是它——打完一局再开选人页，
	# 会显示上一局剩的钱。读档那条路同理（见 load_run）。
	player_data = character_data.duplicate()
	player_data.reset_for_new_run()
	_apply_permanent_upgrades()
	current_deck.clear()
	current_relics.clear()
	# 遗物有两个去处：current_relics 是「这一局有哪些」，RelicManager 是「每场战斗都在听
	# 信号的那批监听者」。只清前者的话，上一局的遗物会接着在新局里响——开局自带的那件
	# 是靠下面的 add_relic 重新入册的，所以顺序必须是先清后加。
	RelicManager.clear_relics()
	visited_node_ids.clear()
	seen_event_ids.clear()
	current_chapter = 1
	current_floor = 0
	current_encounter_type = MapNodeData.NodeType.BATTLE
	current_gold = player_data.gold
	potion_manager = PotionManager.new()
	pending_reward = {}
	clear_map_state()
	_deck_snapshot.clear()
	run_enemies_killed = 0
	run_bosses_killed = 0
	run_elapsed_seconds = 0
	_play_accumulator = 0.0
	_unflushed_seconds = 0
	# 进阶难度在这里快照成本局的一份：之后无论账号解锁到几级，这一局都按开局选的算。
	# record_run_completion() 会把 ascension_level 往上推，结束后再取就会记成别的难度。
	var bal := DataManager.get_balance()
	var unlocked := clampi(meta_progress.ascension_level if meta_progress else 1, 1,
		bal.max_ascension if bal else MAX_ASCENSION)
	run_ascension = clampi(ascension, 1, unlocked) if ascension >= 0 else unlocked
	# 记住这次选用的难度，下次开新局的选择器默认停在它上面。只记「真选过」的那一种，
	# 没传级数的入口（-1）不覆盖——否则测试和老调用点会把玩家的选择冲掉。
	# 这里就得落盘：中途退出（没走到 finish_run）也得记住。
	if ascension >= 0 and meta_progress != null:
		meta_progress.last_ascension_choice = run_ascension
		save_meta_progress()
	_seed_run(seed_value)
	resume_screen = GameScreen.MAP
	node_state = {}
	for card_id in player_data.starting_deck_ids:
		var card := DataManager.get_card(card_id)
		if card:
			add_card_to_deck(card)
		else:
			var default := CardData.new()
			default.card_id = card_id
			default.card_name = card_id
			default.card_type = CardData.CardType.ATTACK
			default.rarity = CardData.CardRarity.BASIC
			default.cost = 1
			default.base_damage = 6
			default.description_template = "造成 {damage} 点伤害。"
			default.target_type = CardData.TargetType.SINGLE_ENEMY
			current_deck.append(default)
	if not player_data.starting_relic_id.is_empty():
		var relic := DataManager.get_relic(player_data.starting_relic_id)
		if relic:
			add_relic(relic)
	mark_cards_seen(current_deck)
	EventBus.run_started.emit()
	change_screen(GameScreen.MAP)

## 给这一局的随机数发生器播种。种子本身用全局随机源抽——抽种子是唯一不需要可复现的一步，
## 而且全局源在引擎启动时已经自动播过种了。
func _seed_run(seed_value: int) -> void:
	run_seed = seed_value if seed_value > 0 else randi_range(SEED_MIN, SEED_MAX)
	run_rng.seed = run_seed

## Array.pick_random() / Array.shuffle() 内部走的是引擎全局随机源，改不了，
## 所以玩法随机要用这两个替代品，才能保证同一个种子抽出来的东西一样。
func rand_pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[run_rng.randi_range(0, arr.size() - 1)]

## 按权重抽一个，权重和 items 按下标一一对应。权重是数据填的（比如普通敌人的
## 最早出场楼层），填漏了不该让抽奖整个失灵——总权重为 0 就退回均匀抽样。
func rand_pick_weighted(items: Array, weights: Array) -> Variant:
	var n := mini(items.size(), weights.size())
	if n <= 0:
		return rand_pick(items)
	var total := 0.0
	for i in n:
		total += maxf(0.0, float(weights[i]))
	if total <= 0.0:
		return rand_pick(items.slice(0, n))
	var roll := run_rng.randf_range(0.0, total)
	for i in n:
		roll -= maxf(0.0, float(weights[i]))
		if roll <= 0.0:
			return items[i]
	return items[n - 1]

## Fisher–Yates，就地打乱。
func rand_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := run_rng.randi_range(0, i)
		var swap: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = swap

func _apply_permanent_upgrades() -> void:
	if meta_progress == null:
		return
	var upg: Dictionary = meta_progress.permanent_upgrades
	player_data.max_hp += int(upg.get("max_hp", 0)) * 5
	player_data.current_hp = player_data.max_hp
	player_data.gold += int(upg.get("gold", 0)) * 15
	player_data.strength += int(upg.get("strength", 0))

## 卡组里装的永远是副本，不是 DataManager.card_database 里那一份共享对象。
## 商店和卡牌奖励传给这里的都是卡池里那一份，若不复制，休息站的升级（upgrade() 是就地改，
## 会给名字加「+」）会改到卡池本体，之后百科和所有抽取都会跟着变。
func add_card_to_deck(card: CardData) -> void:
	var copy := card.duplicate() as CardData
	current_deck.append(copy)
	EventBus.card_added_to_deck.emit(copy)

func remove_card_from_deck(card: CardData) -> bool:
	var idx := current_deck.find(card)
	if idx >= 0:
		current_deck.remove_at(idx)
		EventBus.card_removed_from_deck.emit(card)
		return true
	return false

## 玩家点名升一张（休息点自己从牌组里挑）。带两道门：不在牌组里的、已经升过的都不收，
## 免得选卡器把一份副本传回来就把卡池里那份原始数据也一起升了。
func upgrade_card(card: CardData) -> bool:
	if card == null or card.upgraded or not current_deck.has(card):
		return false
	card.upgrade()
	EventBus.card_upgraded.emit(card)
	return true

func upgrade_card_random() -> CardData:
	if current_deck.is_empty():
		return null
	var idx := run_rng.randi_range(0, current_deck.size() - 1)
	current_deck[idx].upgrade()
	EventBus.card_upgraded.emit(current_deck[idx])
	return current_deck[idx]

## 战斗之外改血量的唯一入口（休息站治愈、事件页扣血）。
## 直接写 player_data.current_hp 的话没人发信号，全局横条会停在上一次的值上——
## 战斗里改血是走 player_data.take_damage/heal 的，那条路自己会发 player_hp_changed。
func set_player_hp(value: int) -> void:
	player_data.current_hp = clampi(value, 0, player_data.max_hp)
	EventBus.player_hp_changed.emit(player_data.current_hp, player_data.max_hp)

func add_gold(amount: int) -> void:
	current_gold += amount
	player_data.gold = current_gold
	EventBus.gold_changed.emit(current_gold)

func spend_gold(amount: int) -> bool:
	if current_gold >= amount:
		current_gold -= amount
		player_data.gold = current_gold
		EventBus.gold_changed.emit(current_gold)
		return true
	return false

func add_souls(amount: int) -> void:
	if amount <= 0 or meta_progress == null:
		return
	meta_progress.souls += amount
	save_meta_progress()

func spend_souls(amount: int) -> bool:
	if meta_progress == null or meta_progress.souls < amount:
		return false
	meta_progress.souls -= amount
	save_meta_progress()
	return true

## 把卡牌记入百科大全的「遇见过」。卡牌奖励、商店、起始卡组都走这里。
func mark_cards_seen(cards: Array) -> void:
	if meta_progress == null:
		return
	var changed := false
	for card: Variant in cards:
		if card is CardData and meta_progress.mark_seen_card((card as CardData).card_id):
			changed = true
	if changed:
		save_meta_progress()

## 敌人血量按本局开局快照那一级难度放大，不是账号解锁的最高级：账号解锁到 8 了，
## 这一局选的难度 1 也还是一级的血量。再叠上「第几章」那一档——同样的难度下第 3 章比第 1 章硬。
## 开场组队、召唤援兵、分裂小怪三条生成路径都得走这里，少走一处那一批敌人就漏了加成。
func scale_enemy_for_run(data: EnemyData) -> EnemyData:
	var copy := data.duplicate() as EnemyData
	var bal := DataManager.get_balance()
	var hp_mult := 1.0
	var damage_mult := 1.0
	if run_ascension > 1:
		var asc_step := bal.ascension_hp_step if bal else 0.05
		hp_mult += asc_step * float(run_ascension - 1)
	if current_chapter > 1:
		var chapters := float(current_chapter - 1)
		hp_mult += (bal.chapter_hp_step if bal else 0.5) * chapters
		damage_mult += (bal.chapter_damage_step if bal else 0.25) * chapters
	if hp_mult == 1.0 and damage_mult == 1.0:
		return copy
	copy.max_hp = int(round(float(copy.max_hp) * hp_mult))
	copy.normal_intent_pattern = _scale_intents(data.normal_intent_pattern, damage_mult)
	copy.aggressive_intent_pattern = _scale_intents(data.aggressive_intent_pattern, damage_mult)
	return copy

## 意图的数值乘倍率。**每条都得先 duplicate() 再改**：EnemyData 是浅拷贝，
## copy.normal_intent_pattern 里装的还是 DataManager 里那一批共享资源，
## 就地改 value 会把整个敌人库改掉——之后这一整局、连百科里的数值都跟着变。
## 和 add_card_to_deck() 里「卡组装副本」是同一个坑。
func _scale_intents(patterns: Array[IntentResource], mult: float) -> Array[IntentResource]:
	var out: Array[IntentResource] = []
	for intent in patterns:
		if intent == null or mult == 1.0:
			out.append(intent)
			continue
		var scaled := intent.duplicate() as IntentResource
		scaled.value = int(round(float(scaled.value) * mult))
		out.append(scaled)
	return out

## 把敌人记入百科大全的「遇见过」。战斗开场生成敌人时调用。
func mark_enemies_seen(enemies: Array) -> void:
	if meta_progress == null:
		return
	var changed := false
	for enemy: Variant in enemies:
		if enemy is EnemyData and meta_progress.mark_seen_enemy((enemy as EnemyData).enemy_id):
			changed = true
	if changed:
		save_meta_progress()

## 遗物池只有十几件，精英/Boss/宝箱又都会发，同一件被发第二次是会发生的。
## 不去重的话 current_relics 会写进重复的 relic_id，遗物栏、局史、收集成就计数全部跟着失真。
func add_relic(relic: RelicData) -> void:
	if relic == null or has_relic(relic.relic_id):
		return
	current_relics.append(relic)
	RelicManager.add_relic(relic)
	if meta_progress != null and meta_progress.mark_obtained_relic(relic.relic_id):
		save_meta_progress()

func has_relic(relic_id: String) -> bool:
	for relic in current_relics:
		if relic.relic_id == relic_id:
			return true
	return false

## 充能遗物还剩几次。额度的账本在 RelicManager 手里（它才是每场战斗都在听信号的那个），
## 这里只转发——界面和测试都从这一条路取，免得两边各记一份。
func get_relic_charges(relic_id: String) -> int:
	return RelicManager.get_charges(relic_id)

func add_potion(potion: PotionData) -> bool:
	_ensure_potion_manager()
	var added := potion_manager.add_potion(potion) >= 0
	if added and meta_progress != null and meta_progress.mark_found_potion(potion.potion_id):
		save_meta_progress()
	return added

func use_potion(slot_index: int, bm: Variant = null, target: EnemyBase = null) -> PotionData:
	_ensure_potion_manager()
	return potion_manager.use_potion(slot_index, bm, target)

func get_potion_slots() -> Array:
	_ensure_potion_manager()
	return potion_manager.potion_slots

func save_run(slot: int = -1) -> void:
	if slot < 0:
		slot = current_save_slot
	var run := RunData.new()
	run.populate()
	var dict := run.to_dict()
	dict["saved_at"] = Time.get_datetime_string_from_system()
	dict["map"] = _serialize_map()
	dict["resume_screen"] = int(resume_screen)
	dict["node_state"] = node_state
	dict["encounter_type"] = int(current_encounter_type)
	var f := FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(dict, "\t"))
		f.close()
	else:
		push_error("[GameManager] save_run failed to open %s" % get_save_path(slot))

func load_run(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_save_slot
	var dict := _read_save_dict(slot)
	if dict.is_empty():
		return false
	var run := RunData.new()
	run.from_dict(dict)
	# 角色资源必须在 apply_to_player() 之前接回来。apply_to_player 只还原数值和局内状态，
	# 而头像、流派色、角色名这些「这个人是谁」的字段挂在角色资源上。漏了这一步，
	# player_data 还是 _ready() 里创建的默认剑客（portrait 为空），
	# ArtSwap 拿不到贴图就把纯色占位块留在场上；卡池归属、横条名字、游玩时长归属也会错。
	var character := DataManager.get_character(run.character_id)
	if character == null:
		# 存档里的角色 id 在库里找不到（资源改名/删角色）时别退回**没有立绘**的空壳：
		# 那正是玩家报的纯色块。至少借一个真角色资源把美术接上，名字和卡池会跟存档不符，
		# 但这是内容被改名后才走到的兜底，警告已经足够定位。
		var fallback := DataManager.characters_in_order()
		if not fallback.is_empty():
			character = fallback[0]
			push_warning("[GameManager] 存档角色 %s 不在角色库里，按默认角色 %s 继续" % [
				run.character_id, character.character_id])
		else:
			push_warning("[GameManager] 存档角色 %s 不在角色库里，角色库也是空的，按空壳继续" % run.character_id)
			character = PlayerData.new()
			character.character_id = run.character_id
	# 同 start_new_run：角色库里的实例是共享的，读档把本局血量/金币写上去会污染角色库。
	player_data = character.duplicate()
	run.apply_to_player()
	if player_data.portrait == null:
		# 立绘路径填错 / 图没导入时，战斗里 ArtSwap 换不了图，玩家看到的还是纯色块。
		# 这类「静默退回占位美术」要在读档时先喊一声，不能等玩家截图来报。
		push_warning("[GameManager] 角色 %s 没有立绘资源，战斗里会留下纯色占位块" % player_data.character_id)
	if dict.has("map"):
		_deserialize_map(dict["map"])
	# 进战斗前那一步就要把遭遇类型带着，否则读档重开 BOSS 战会被当成普通战斗。
	current_encounter_type = int(dict.get("encounter_type", MapNodeData.NodeType.BATTLE)) as MapNodeData.NodeType
	resume_screen = int(dict.get("resume_screen", GameScreen.MAP)) as GameScreen
	var raw_state: Variant = dict.get("node_state", {})
	node_state = raw_state if typeof(raw_state) == TYPE_DICTIONARY else {}
	# pending_reward 是「刚打完的那场战斗 → 奖励页」的内存桥，读档进来没有这场战斗。
	# 不清的话，从另一个存档跳过来时旧局的金币/药水会混进这次奖励的快照。
	pending_reward = {}
	current_save_slot = slot
	return true

func _serialize_map() -> Dictionary:
	if _saved_map_layers.is_empty():
		return {}
	var layers_data: Array = []
	for layer in _saved_map_layers:
		var nodes_data: Array = []
		for node in layer.nodes:
			nodes_data.append(node.to_dict())
		layers_data.append({"floor": layer.floor, "nodes": nodes_data})
	return {
		"player_node_id": _saved_player_node_id,
		"layers": layers_data,
	}

func _deserialize_map(data: Dictionary) -> void:
	_saved_map_layers.clear()
	_saved_player_node_id = str(data.get("player_node_id", ""))
	var node_map: Dictionary = {}
	var layers: Array = []
	for layer_data in data.get("layers", []):
		var layer = MapGenerator.MapLayer.new(int(layer_data.get("floor", 0)))
		for node_data in layer_data.get("nodes", []):
			var node := MapNodeData.from_dict(node_data)
			layer.nodes.append(node)
			node_map[node.node_id] = node
		layers.append(layer)
	for layer_data in data.get("layers", []):
		for node_data in layer_data.get("nodes", []):
			var node: MapNodeData = node_map.get(str(node_data.get("node_id", "")), null)
			if node == null:
				continue
			node.connections.clear()
			for conn_id in node_data.get("connections", []):
				var conn: MapNodeData = node_map.get(str(conn_id), null)
				if conn:
					node.connections.append(conn)
	_saved_map_layers = layers

func _read_save_dict(slot: int) -> Dictionary:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))

func delete_run(slot: int) -> void:
	var path := get_save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func get_save_summary(slot: int) -> Dictionary:
	var dict := _read_save_dict(slot)
	if dict.is_empty():
		return {}
	var char_name := ""
	var char := DataManager.get_character(str(dict.get("character_id", "")))
	if char:
		char_name = char.character_name
	return {
		"slot": slot,
		"character_id": str(dict.get("character_id", "")),
		"character_name": char_name,
		"floor": int(dict.get("floor", 0)),
		"current_hp": int(dict.get("current_hp", 0)),
		"max_hp": int(dict.get("max_hp", 0)),
		"gold": int(dict.get("gold", 0)),
		"ascension": int(dict.get("ascension", 1)),
		"saved_at": str(dict.get("saved_at", "")),
	}

var _saved_map_layers: Array = []
var _saved_player_node_id: String = ""

func save_map_state(layers: Array, player_node_id: String) -> void:
	_saved_map_layers = layers
	_saved_player_node_id = player_node_id

func has_map_state() -> bool:
	return not _saved_map_layers.is_empty()

func get_map_state() -> Dictionary:
	return {
		"layers": _saved_map_layers,
		"player_node_id": _saved_player_node_id
	}

func clear_map_state() -> void:
	_saved_map_layers.clear()
	_saved_player_node_id = ""

var _deck_snapshot: Array[CardData] = []

func save_deck_snapshot() -> void:
	_deck_snapshot.clear()
	for card in current_deck:
		_deck_snapshot.append(card.duplicate())

func restore_deck_snapshot() -> void:
	if _deck_snapshot.is_empty():
		return
	current_deck.clear()
	for card in _deck_snapshot:
		current_deck.append(card)
	_deck_snapshot.clear()

func get_deck_size() -> int:
	return current_deck.size()

func get_run_data() -> RunData:
	var run := RunData.new()
	run.populate()
	return run

func _load_meta_progress() -> void:
	meta_progress = MetaProgress.new()
	if FileAccess.file_exists(META_SAVE_PATH):
		var f := FileAccess.open(META_SAVE_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				meta_progress.from_dict(parsed as Dictionary)
	elif ResourceLoader.exists(LEGACY_META_SAVE_PATH):
		meta_progress = ResourceLoader.load(LEGACY_META_SAVE_PATH) as MetaProgress
		save_meta_progress()

func save_meta_progress() -> void:
	if meta_progress == null:
		return
	var f := FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta_progress.to_dict(), "\t"))
		f.close()

func record_run_completion() -> void:
	meta_progress.highest_floor_cleared = maxi(meta_progress.highest_floor_cleared, current_floor)
	var bal := DataManager.get_balance()
	var max_asc := bal.max_ascension if bal else MAX_ASCENSION
	# 解锁跟着「这一局打的哪一级」走，不是赢一次就加一级：
	# 否则通关难度 1 反复刷也能一路解锁到顶，难度就白分了。
	var next_level := run_ascension + 1
	if next_level > meta_progress.ascension_level:
		meta_progress.ascension_level = mini(next_level, max_asc)
	meta_progress.souls += BOSS_SOUL_BONUS

func record_run_defeat() -> void:
	meta_progress.highest_floor_cleared = maxi(meta_progress.highest_floor_cleared, current_floor)


# --- 对局收尾：唯一的写盘点 ---

func get_run_history() -> RunHistory:
	if run_history == null:
		run_history = RunHistory.load_from_disk()
	return run_history

## 一局结束时调用一次。end_state.gd 的两个分支各调一次，别的地方不许调。
## 顺序：快照 → 算分 → 写历史 → 更新计数器 → 评估成就 → 发信号 → 存档。
func finish_run(victory: bool) -> void:
	if meta_progress == null:
		return
	var snapshot := get_run_data().to_dict()
	var character_id := str(snapshot.get("character_id", ""))
	if character_id.is_empty():
		return
	# 随机流状态是存档用的，历史记录里留着只是一串没用的长数字。
	snapshot.erase("rng_state")

	# flush 已经把大部分时长记进 meta 了，这里只补它没记的那段，别重复累加。
	var flushed := _flush_play_seconds()
	var elapsed := run_elapsed_seconds
	snapshot["character_name"] = _character_name(character_id)
	snapshot["victory"] = victory
	snapshot["duration_seconds"] = elapsed
	snapshot["played_at"] = Time.get_datetime_string_from_system()
	snapshot["score"] = RunHistory.compute_score(snapshot)

	var history := get_run_history()
	history.append(snapshot)
	history.save_to_disk()

	var entry := meta_progress.stats_for(character_id)
	entry["runs"] = int(entry.get("runs", 0)) + 1
	entry["floors_climbed"] = int(entry.get("floors_climbed", 0)) + current_floor
	entry["enemies_killed"] = int(entry.get("enemies_killed", 0)) + run_enemies_killed
	entry["bosses_killed"] = int(entry.get("bosses_killed", 0)) + run_bosses_killed
	entry["play_seconds"] = int(entry.get("play_seconds", 0)) + (elapsed - flushed)
	entry["fastest_win_seconds"] = int(entry.get("fastest_win_seconds", -1))
	meta_progress.record_best_floor(character_id, current_floor)
	if victory:
		entry["wins"] = int(entry.get("wins", 0)) + 1
		meta_progress.record_win_time(character_id, elapsed)
	else:
		entry["deaths"] = int(entry.get("deaths", 0)) + 1

	if victory:
		record_run_completion()
	else:
		record_run_defeat()

	evaluate_achievements()
	save_meta_progress()

	if victory:
		EventBus.run_won.emit()
	else:
		EventBus.run_lost.emit()
	_play_accumulator = 0.0
	_unflushed_seconds = 0

	# 这一局已经收摊了，槽位留着只会让「继续游戏」把人送回一局打完的存档里。
	# 必须放在最后：上面的 get_run_data() 还要读玩家状态。
	resume_screen = GameScreen.MAP
	node_state = {}
	delete_run(current_save_slot)

func _character_name(character_id: String) -> String:
	var character := DataManager.get_character(character_id)
	return character.character_name if character else character_id


# --- 成就评估 ---

## 逐个成就对照当前进度，达成即写入解锁列表。条件全是「只增不减」，重复调用无副作用。
func evaluate_achievements() -> void:
	if meta_progress == null:
		return
	for achievement: Achievement in DataManager.achievement_database.values():
		if meta_progress.has_achievement(achievement.achievement_id):
			continue
		if _achievement_reached(achievement):
			meta_progress.mark_achievement(achievement.achievement_id)

func _achievement_reached(achievement: Achievement) -> bool:
	match achievement.condition:
		Achievement.Condition.WINS:
			return meta_progress.stat_total("wins") >= achievement.threshold
		Achievement.Condition.DEATHS:
			return meta_progress.stat_total("deaths") >= achievement.threshold
		Achievement.Condition.ENEMIES_KILLED:
			return meta_progress.stat_total("enemies_killed") >= achievement.threshold
		Achievement.Condition.BOSSES_KILLED:
			return meta_progress.stat_total("bosses_killed") >= achievement.threshold
		Achievement.Condition.FLOORS_CLIMBED:
			return meta_progress.stat_total("floors_climbed") >= achievement.threshold
		Achievement.Condition.FASTEST_WIN:
			var best := meta_progress.fastest_win()
			# -1 表示还没赢过，不能被当成「很快通关」。
			return best > 0 and best <= achievement.threshold
		Achievement.Condition.ASCENSION:
			return meta_progress.ascension_level >= achievement.threshold
		Achievement.Condition.SOULS:
			return meta_progress.souls >= achievement.threshold
		Achievement.Condition.ALL_CARDS:
			return meta_progress.seen_card_ids.size() >= DataManager.card_database.size()
		Achievement.Condition.ALL_POTIONS:
			return meta_progress.found_potion_ids.size() >= DataManager.potion_database.size()
		Achievement.Condition.ALL_ENEMIES:
			return meta_progress.seen_enemy_ids.size() >= DataManager.codex_enemy_count()
		Achievement.Condition.ALL_RELICS:
			return _relics_obtained(achievement.rarity_filter) >= _relics_total(achievement.rarity_filter)
	return false

func _relics_obtained(rarity_filter: int) -> int:
	var count := 0
	for relic_id in meta_progress.obtained_relic_ids:
		var relic := DataManager.get_relic(relic_id)
		if relic and (rarity_filter < 0 or int(relic.rarity) == rarity_filter):
			count += 1
	return count

func _relics_total(rarity_filter: int) -> int:
	var count := 0
	for relic: RelicData in DataManager.relic_database.values():
		if rarity_filter < 0 or int(relic.rarity) == rarity_filter:
			count += 1
	return count
