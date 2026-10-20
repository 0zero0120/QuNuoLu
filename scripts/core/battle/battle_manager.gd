class_name BattleManager
extends Control

@export var max_player_energy: int = 3
@export var cards_per_turn: int = 5

@onready var hand_container: Control = %HandContainer
@onready var enemy_slots: Control = %EnemySlots
@onready var player_node: Player = %PlayerNode
@onready var end_turn_button: Button = %EndTurnButton
@onready var energy_display_label: Label = %EnergyDisplayLabel
@onready var draw_pile_button: Button = %DrawPileButton
@onready var discard_pile_button: Button = %DiscardPileButton
@onready var exhaust_pile_button: Button = %ExhaustPileButton
@onready var player_status_bar: HBoxContainer = $PlayerStatusBar
@onready var background_image: TextureRect = $BackgroundImage

var player: Player
var enemies: Array[EnemyBase] = []
var card_pile: CardPile
var energy_system: EnergySystem
var state_machine: StateMachine
var selected_card: Card = null
## 正等着玩家指目标的药水槽号，-1 表示不在这个状态。药水横条挂在全局层（RunHud）上、
## 够不着战斗状态机，所以「待指目标」这件事记在战斗上，由 PlayerTurnState 自己每帧读它：
## 读到了就点亮敌人、接下那一次点击。见 _process / handle_input。
var pending_potion_slot: int = -1
## 正一段一段结算一张多段牌。这零点几秒里再点一张牌，两张的效果会叠在一起，
## 节拍也就白做了——所以解析期间新出牌一律早退、结束回合按钮按不动。见 play_card。
var _resolving: bool = false
var turn_number: int = 0
var _safety_check_timer: float = 0.0
var _status_overlay: StatusOverlay = null

## 手牌快选：数字键挨个对应手牌里的第 1~10 张，第 10 张用 0。
## 键位固定、不开放改绑——参考界面那张按键表里也没有这几行。
## 场上最多站几只。战斗场景里 EnemySlots 是个 HBox，三个 200 宽的位子刚好排得下不重叠；
## 第四个会把布局挤出去。开场组队、召唤、分裂三条路都得受它约束。
const MAX_ENEMY_SLOTS: int = 3

## 每章的柔和提亮强度（0 就是不开）。第二章背景整体压得很暗，深色水墨剪影站上去
## 会和背景糊成一片，所以只给它补一层中间亮、往外淡出的白光；另两章本身够亮，加了反而发灰。
const CHAPTER_KEY_LIGHT: Dictionary = {1: 0.0, 2: 0.26, 3: 0.0}

## 章节底图的压暗倍率。三张底图是白纸水墨，实测平均亮度 105~217（满值 254），而场上
## 敌人名、血量数字、战报行都是默认白字且不带描边——直接压上去等于隐形。乘一个系数
## 相当于盖一层黑蒙版（不透明贴图上 modulate 与叠色等价），文字主要靠 6px 黑描边兜住。
##
## 0.36 是第一版算出来的值，当时只验了「文字读得清」，没验「画面还好看」——第 1、3 章
## 原图均值 204/217，压完只剩 68/74，玩家一看就说「黑不溜秋」。0.55 是玩家自己挑的：
## 第 1/3 章回到接近原图的观感，亮点落到 140 上下，黑描边还压得住白字。
const BG_DIM := Color(0.55, 0.55, 0.58)

## 底图动效。三张底图原本是静的，这里各配一组极缓的动作，让画面「是活的」又不抢戏：
## 第 1 章水面雾气升腾、第 2 章漩涡极缓自转 + 雾气翻涌、第 3 章云海翻涌 + 天光呼吸。
## 三章共用一份 shader，差别只有这几个 uniform——加新章就加一行预设。
##
## 尺度是「纯加法」：雾只往上混一层，被压暗的画面的一个像素都不动；漩涡那项是有界摆动，
## 半径之外完全静止。（第一版做成全图 UV 位移，山树云全跟着晃，玩家评价「树都在抽搐」。）
const BG_SHADER_PATH := "res://assets/shaders/battle_bg_motion.gdshader"
const BG_MOTION: Dictionary = {
	# 第 1 章是白纸水墨（原图均值 217），水本来就画得发白，纯白色雾压上去等于没画
	# （第一版实测帧间最大差才 33/255，玩家原话「看不到有一点变化」）。这里雾色用 >1 的 HDR 值
	# 并偏冷，亮度差被 BG_DIM 一起缩掉后仍比画面亮一截；阈值拉窄成丝缕，只在水面飘一层。
	1: {"fog_strength": 1.0, "fog_low": 0.56, "fog_high": 0.98, "fog_scale": 5.0, "fog_rise": 1.8,
		"fog_thr_low": 0.48, "fog_thr_high": 0.76,
		"fog_color": Color(1.34, 1.38, 1.50)},
	# 第 2 章底图本身云就厚，再叠一层会糊住山——雾压到最轻，只在下半透一点气，主戏交给漩涡。
	2: {"fog_strength": 0.38, "fog_low": 0.46, "fog_high": 0.95, "fog_scale": 4.5, "fog_rise": 0.8,
		"fog_thr_low": 0.50, "fog_thr_high": 0.82,
		"fog_color": Color(0.90, 0.93, 0.96),
		"swirl_strength": 0.22, "swirl_center": Vector2(0.518, 0.715), "swirl_radius": 0.40},
	3: {"fog_strength": 0.72, "fog_low": 0.0, "fog_high": 1.15, "fog_scale": 4.0, "fog_rise": 1.4,
		"fog_thr_low": 0.38, "fog_thr_high": 0.76,
		"fog_color": Color(0.99, 1.00, 1.03),
		"glow_strength": 0.12, "glow_center": Vector2(0.5, 0.30), "glow_color": Color(1.0, 0.86, 0.62)},
}

const PLAY_KEY_LABELS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
const PLAY_KEYCODES: Array[int] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
]


## 按下的键对应手牌里第几张（0 开始）。不是数字键就返回 -1。
static func play_key_index(keycode: int) -> int:
	return PLAY_KEYCODES.find(keycode)


static func instantiate_card_scene() -> PackedScene:
	return load("res://scenes/battle/card.tscn")

func _ready() -> void:
	var bal := DataManager.get_balance()
	if bal:
		max_player_energy = bal.base_energy
		cards_per_turn = bal.cards_per_turn
	player = player_node
	energy_system = EnergySystem.new(max_player_energy)
	card_pile = CardPile.new()
	add_child(card_pile)
	_build_state_machine()
	EventBus.energy_changed.connect(_on_energy_changed)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	card_pile.pile_changed.connect(_update_pile_counts)
	# 全局横条靠这个判「药水现在能不能用」：没有战斗上下文时，
	# 能量/格挡/群伤那几种药水会被白白消耗掉、什么都不发生。
	GameManager.active_battle = self
	if end_turn_button:
		# 开了「长按确认」就得按住一会儿才算数，免得手滑一下回合就没了。
		HoldToConfirm.attach(end_turn_button, _on_end_turn_pressed, SettingsManager.hold_to_confirm)
		end_turn_button.tooltip_text = "结束当前回合（按住不放）" if SettingsManager.hold_to_confirm \
				else "结束当前回合"
		end_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if energy_display_label:
		energy_display_label.tooltip_text = "当前能量 / 最大能量"
		energy_display_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_connect_pile_button(draw_pile_button, "抽牌堆剩余卡牌数", _on_draw_pile_pressed)
	_connect_pile_button(discard_pile_button, "弃牌堆卡牌数", _on_discard_pile_pressed)
	_connect_pile_button(exhaust_pile_button, "本局消耗掉的卡牌数", _on_exhaust_pile_pressed)
	_player_connect_signals()
	_apply_chapter_background()
	_apply_chapter_key_light()
	_update_player_status_display()
	_layout_combatants()
	var player_area := player_node.get_parent() as Control
	if player_area:
		player_area.resized.connect(_layout_combatants)
	enemy_slots.resized.connect(_layout_combatants)
	$PlayHistory.clear_history()
	start_battle()
	_show_tutorial_if_needed()


## 章节背景。三章各一张，横向铺满整个战斗区。图读不到就留下面那块 ColorRect
## 兜底——还是原来那片深蓝黑，不至于开一个透明天窗出来。
func _apply_chapter_background() -> void:
	if background_image == null:
		return
	var chapter := clampi(GameManager.current_chapter, 1, GameManager.CHAPTER_COUNT)
	var path := "res://assets/art/backgrounds/ch%d.jpg" % chapter
	if ResourceLoader.exists(path):
		background_image.texture = load(path)
		# 压暗到能读字的程度。取不到图时不动它——下面那块 Background ColorRect 兜底，
		# 本来就是深色，再乘一遍只会更黑。
		background_image.modulate = BG_DIM
		_apply_background_motion(chapter)


## 给底图挂动效材质。没有预设（以后加的新章）或 shader 丢了就把 material 清成 null，
## 退回原来那张一动不动的图——底图不依赖它，坏了也只是不动，不会开出个天窗。
func _apply_background_motion(chapter: int) -> void:
	var preset: Dictionary = BG_MOTION.get(chapter, {})
	if preset.is_empty() or not ResourceLoader.exists(BG_SHADER_PATH):
		background_image.material = null
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(BG_SHADER_PATH)
	for key: String in preset.keys():
		mat.set_shader_parameter(key, preset[key])
	background_image.material = mat


## 战场区垫一层柔光。垫在两块区域的最底下（child 0），立绘和血条都盖在它上面，
## 所以它只提亮背景、不会把文字洗白。径向渐变天生是中间亮、边缘淡出，
## 不会像叠一块半透明白矩形那样在区域边界上留一道硬边。
func _apply_chapter_key_light() -> void:
	var alpha: float = CHAPTER_KEY_LIGHT.get(GameManager.current_chapter, 0.0)
	if alpha <= 0.0:
		return
	for area_name in ["PlayerArea", "EnemyArea"]:
		var area := get_node_or_null(area_name) as Control
		if area == null:
			continue
		var light := TextureRect.new()
		light.name = "ChapterKeyLight"
		light.texture = _make_key_light_texture(alpha)
		light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 按短边适配成一枚正圆光斑：区域是扁的，拉伸成椭圆会显得像一块没擦干净的灰。
		light.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		light.anchors_preset = PRESET_FULL_RECT
		light.anchor_right = 1.0
		light.anchor_bottom = 1.0
		area.add_child(light)
		area.move_child(light, 0)


func _make_key_light_texture(alpha: float) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, alpha))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	# 默认 64x64 铺到 400 多像素上会看出色带，抬到 512 就平滑了。
	tex.width = 512
	tex.height = 512
	return tex


func _exit_tree() -> void:
	if GameManager.active_battle == self:
		GameManager.active_battle = null

## 战斗中的快捷键。设定页那张表负责「哪个键」，这里只负责「按了做什么」。
## 「查看牌组」不在这儿——那看的是**这一局整副牌组**，归全局层（GameManager._unhandled_input）。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("draw_pile"):
		_on_draw_pile_pressed()
	elif event.is_action_pressed("discard_pile"):
		_on_discard_pile_pressed()
	elif event.is_action_pressed("exhaust_pile"):
		_on_exhaust_pile_pressed()
	elif event.is_action_pressed("end_turn"):
		_on_end_turn_pressed()
	elif event.is_action_pressed("view_status"):
		_toggle_status_overlay()
	else:
		return
	get_viewport().set_input_as_handled()


## 底部三个牌堆计数都是按钮（点了就开查看器），接线方式一样，统一走这里。
func _connect_pile_button(button: Button, tooltip: String, handler: Callable) -> void:
	if button == null:
		return
	button.pressed.connect(handler)
	button.tooltip_text = tooltip
	button.mouse_filter = Control.MOUSE_FILTER_STOP


func _toggle_status_overlay() -> void:
	if _status_overlay != null and is_instance_valid(_status_overlay):
		_status_overlay.close()
		_status_overlay = null
		return
	_status_overlay = StatusOverlay.new()
	_status_overlay.setup(player, enemies)
	get_parent().add_child(_status_overlay)


func _show_tutorial_if_needed() -> void:
	if GameManager.meta_progress == null or GameManager.meta_progress.tutorial_seen:
		return
	var overlay: Control = load("res://scripts/ui/tutorial_overlay.gd").new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_parent().add_child(overlay)

func _player_connect_signals() -> void:
	player.strength_changed.connect(func(v: int): _update_player_status_display(); _update_hand_playable())
	player.dexterity_changed.connect(func(v: int): _update_player_status_display(); _update_hand_playable())
	player.block_changed.connect(func(v: int): _update_player_status_display())
	player.status_effects_changed.connect(func(): _update_player_status_display(); _update_hand_playable())

func _update_player_status_display() -> void:
	for child in player_status_bar.get_children():
		child.queue_free()

	var s := player.get_strength()
	var d := player.get_dexterity()
	if s > 0:
		player_status_bar.add_child(_make_status_label("💪%d" % s, "力量 +%d：每段攻击伤害 +%d" % [s, s], Color(0.9, 0.35, 0.25)))
	if s < 0:
		player_status_bar.add_child(_make_status_label("💪%d" % s, "力量 %d" % s, Color(0.6, 0.3, 0.3)))
	if d > 0:
		player_status_bar.add_child(_make_status_label("⚡%d" % d, "敏捷 +%d：所有格挡 +%d" % [d, d], Color(0.35, 0.55, 0.9)))
	if d < 0:
		player_status_bar.add_child(_make_status_label("⚡%d" % d, "敏捷 %d" % d, Color(0.3, 0.3, 0.6)))
	if player.current_block > 0:
		player_status_bar.add_child(_make_status_label("🛡%d" % player.current_block, "格挡 %d" % player.current_block, Color(0.5, 0.7, 1.0)))

	# 这一圈不能缩在「有格挡」那个 if 里面：虚弱、易伤这些跟格挡没关系，
	# 缩进去会变成「没格挡就看不见身上的状态」。
	for effect in player.status_effects:
		if effect.type == StatusEffect.Type.STRENGTH or effect.type == StatusEffect.Type.DEXTERITY:
			continue
		if effect.value > 0:
			player_status_bar.add_child(_make_status_label("%s%d" % [effect.get_icon(), effect.value], effect.get_tooltip(), effect.get_color()))


func _make_status_label(text: String, tooltip: String, color: Color) -> Panel:
	var panel := Panel.new()
	panel.tooltip_text = tooltip
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(28, 22)
	var style := StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchors_preset = PRESET_FULL_RECT
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 13)
	panel.add_child(lbl)
	return panel

## 药水槽和那个确认框都搬进全局横条了（药水是「这一局的」，不是「这一场的」）。
## 这里只留一行转发，敌人回合那两处调用一个字都不用改。
func set_potions_active(active: bool) -> void:
	if GameManager.run_hud != null and is_instance_valid(GameManager.run_hud):
		GameManager.run_hud.set_potions_active(active)


## 设定页把「战斗动态效果」改了之后当场生效，不用等下一场。只经营待机那一路——
## 受击和出手都是事件驱动的，每次触发现读开关，本来就不用管。
func refresh_unit_motion() -> void:
	var on := SettingsManager.battle_motion
	if player != null:
		player.set_motion_enabled(on)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_motion_enabled(on)


## 敌我在同一条水平线上：两边都拿各自容器的垂直中线当轴心。
## 敌人以前写死 y=168、玩家按容器算一半，窗口一改变比例（1080 高时差八十多像素）。
func _layout_combatants() -> void:
	var player_area := player_node.get_parent() as Control
	if player_area:
		player_node.position = player_area.size / 2.0
	var enemy_y := enemy_slots.size.y / 2.0
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.position.y = enemy_y

func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	add_child(state_machine)
	state_machine.add_state("Init", load("res://scripts/core/battle/battle_states/init_state.gd").new())
	state_machine.add_state("PlayerTurn", load("res://scripts/core/battle/battle_states/player_turn_state.gd").new())
	state_machine.add_state("EnemyTurn", load("res://scripts/core/battle/battle_states/enemy_turn_state.gd").new())
	state_machine.add_state("Resolve", load("res://scripts/core/battle/battle_states/resolve_state.gd").new())
	state_machine.add_state("End", load("res://scripts/core/battle/battle_states/end_state.gd").new())

func start_battle() -> void:
	GameManager.save_deck_snapshot()
	var deck := GameManager.current_deck
	card_pile.initialize(deck)
	player.reset_for_battle(GameManager.player_data)
	state_machine.start("Init")

## 还空着几个敌位。死掉的敌人退场动画放完会把自己那一格整个收起来（见 EnemyBase.
## _play_death_animation），收起来的 Control 不参与 HBox 布局，所以这里也只数看得见的——
## 否则会出现「明明空了一个位子却召唤不出来」。
func free_enemy_slots() -> int:
	var used := 0
	for child in enemy_slots.get_children():
		var slot := child as Control
		if slot and slot.visible:
			used += 1
	return maxi(0, MAX_ENEMY_SLOTS - used)

## 摆一只敌人上场。位子满了就返回 null——召唤和分裂靠这个返回值判「这一只到底出来了没有」。
func spawn_enemy(data: EnemyData) -> EnemyBase:
	if data == null:
		return null
	if free_enemy_slots() <= 0:
		print("[BattleManager] 敌位满了（上限 %d），%s 上不了场" % [MAX_ENEMY_SLOTS, data.display_name])
		return null
	var enemy_scene := load("res://scenes/battle/enemy_character.tscn")
	var enemy: EnemyBase = enemy_scene.instantiate()
	enemy.setup(data)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(200, 400)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(enemy)
	# 槽位宽 200，精灵 ±90 放在正中；纵向等 EnemySlots 布局完再对齐 midline。
	enemy.position = Vector2(100, enemy_slots.size.y / 2.0)
	enemy_slots.add_child(wrapper)
	enemies.append(enemy)
	return enemy

func spawn_enemies(data_list: Array[EnemyData]) -> void:
	for data in data_list:
		spawn_enemy(data)
	EventBus.battle_started.emit(enemies)

func _apply_status_effects(card: CardData, target: Variant) -> void:
	var status_amount := card.get_status_amount()
	for effect_name in card.get_effects_on_target():
		var status_type := _name_to_status_type(effect_name)
		if status_type >= 0:
			if target is EnemyBase:
				(target as EnemyBase).add_status_effect(status_type, status_amount)
			elif target is Player:
				(target as Player).add_status_effect(status_type, status_amount)
			elif card.target_type == CardData.TargetType.ALL_ENEMIES:
				for enemy in get_alive_enemies():
					enemy.add_status_effect(status_type, status_amount)
	for effect_name in card.get_effects_on_self():
		var status_type := _name_to_status_type(effect_name)
		if status_type >= 0:
			player.add_status_effect(status_type, status_amount, card.status_temporary)

func _apply_special_effect(card: CardData) -> void:
	match card.special_effect:
		"upgrade_all_hand":
			for child in hand_container.get_children():
				if child is Card and child.card_data:
					child.card_data.upgrade()
					child.refresh_display(player)
			_update_hand_playable()

func _name_to_status_type(name: String) -> int:
	match name:
		"strength": return StatusEffect.Type.STRENGTH
		"dexterity": return StatusEffect.Type.DEXTERITY
		"weak": return StatusEffect.Type.WEAK
		"vulnerable": return StatusEffect.Type.VULNERABLE
		"ritual": return StatusEffect.Type.RITUAL
		"poison": return StatusEffect.Type.POISON
		"burn": return StatusEffect.Type.BURN
	return -1

func _deal_damage_to_enemy(enemy: EnemyBase, dmg: int, is_weak: bool) -> void:
	# 玩家那一栏也要判：反伤可以在多段攻击打到一半时把玩家反死，
	# 再往下打就成了「死于反伤却把 Boss 也打死，判成通关」。
	if not enemy.is_alive or player == null or not player.is_alive():
		return
	var actual_dmg := dmg
	if is_weak:
		actual_dmg = int(ceil(float(actual_dmg) * 0.75))
	enemy.take_damage(actual_dmg)
	# 震屏接进普通命中，强度**跟着伤害走**：以前只有敌人死亡(9.0)和玩家掉血(7.0)才震，
	# 一拳打上去屏幕纹丝不动，那一下就没有分量。夹在 2.5~11.0，小刀轻推、重击闷响。
	EffectsManager.shake(EffectsManager.shake_for_damage(actual_dmg))
	EventBus.damage_dealt.emit(enemy, actual_dmg, 0)
	_reflect_thorns(enemy)


## 反伤：挂在「玩家出牌打敌人」这条漏斗上，**不能**挂 enemy_base.take_damage——
## 遗物的直伤（relic_effect_resolver 的 deal_aoe）和药水也走那一条，挂那儿玩家会被
## 自己遗物的弹伤反死。按「挨了几下」结算：三段攻击就弹三次，和护体一起惩罚多段。
## 故意不发 damage_dealt：那是「玩家造成伤害」的信号，骨针（每造成一次伤害 +1 力量）
## 会把它当成自己打出的伤害白吃一次充能。伤害数字由 player.take_damage 自己发。
func _reflect_thorns(enemy: EnemyBase) -> void:
	if player == null or not player.is_alive():
		return
	var thorns := enemy.get_total_status_value(StatusEffect.Type.THORNS)
	if thorns <= 0:
		return
	print("[BattleManager] %s 反伤 %d 点" % [enemy.enemy_data.display_name, thorns])
	player.take_damage(thorns)

func _get_damage_targets(target: Variant, card: CardData) -> Array[EnemyBase]:
	if card.target_type == CardData.TargetType.ALL_ENEMIES:
		return get_alive_enemies()
	if target and target is EnemyBase:
		var arr: Array[EnemyBase] = []
		arr.append(target as EnemyBase)
		return arr
	return []

## 出一张牌。**这是个协程**：多段伤害要一段一段打，段与段之间 await 一个节拍——
## 血条一格一格掉、数字一颗一颗蹦、每段各弹一次后仰，玩家才数得清打了几下。
## 单段的牌一次 await 都不走，整条链路和以前逐帧一致（不会平白多出零点几秒的卡顿）。
##
## 调用方**不用 await 它**：弃牌、清选中、判胜负这些收尾晚一两帧落地没有任何影响。
## 解析期间 _resolving 为真，新出牌和「结束回合」都被挡掉，见该变量上面的说明。
func play_card(card: Card, target: Variant = null) -> void:
	if card == null or card.card_data == null:
		return
	# 诅咒是死牌。这里挡一道是最后一道闸——三个入口（点击/拖拽/数字键）都汇到这儿，
	# 上面那两处只是让牌看起来是灰的，真正拦得住的是这一行。
	if card.card_data.unplayable:
		print("[BattleManager] 「%s」不能打出" % card.card_data.card_name)
		return

	var is_weak := player.has_status_of_type(StatusEffect.Type.WEAK)
	var hits := card.card_data.hit_count

	if card.card_data.is_x_cost():
		var x_amount := energy_system.current_energy
		if x_amount <= 0:
			return
		energy_system.spend(x_amount)
		var dmg := card.card_data.get_display_damage(player)
		var blk := card.card_data.get_display_block(player)

		if dmg > 0:
			_begin_resolve()
			_swing_at_enemies()
			var first := true
			for enemy in _get_damage_targets(target, card.card_data):
				for _i in range(x_amount):
					if not enemy.is_alive:
						break
					for _j in range(hits):
						if not enemy.is_alive:
							break
						if not first:
							await _beat()
						first = false
						_deal_damage_to_enemy(enemy, dmg, is_weak)

		if blk > 0:
			player.add_block(blk)
			EventBus.block_gained.emit(player, blk)

		_apply_status_effects(card.card_data, target)
		_apply_special_effect(card.card_data)
		EventBus.card_played.emit(card.card_data, target)
	else:
		var cost := card.card_data.get_display_cost(player)
		if not energy_system.can_spend(cost):
			return
		energy_system.spend(cost)

		var dmg := card.card_data.get_display_damage(player)
		var blk := card.card_data.get_display_block(player)

		if dmg > 0:
			_begin_resolve()
			_swing_at_enemies()
			var first := true
			for enemy in _get_damage_targets(target, card.card_data):
				for _i in range(hits):
					if not enemy.is_alive:
						break
					if not first:
						await _beat()
					first = false
					_deal_damage_to_enemy(enemy, dmg, is_weak)

		if blk > 0:
			player.add_block(blk)
			EventBus.block_gained.emit(player, blk)

		_apply_status_effects(card.card_data, target)
		_apply_special_effect(card.card_data)
		EventBus.card_played.emit(card.card_data, target)

	_end_resolve()

	if card.card_data.exhaust_on_use:
		card_pile.exhaust_card(card)
	else:
		card_pile.discard_card(card)

	var card_parent := card.get_parent()
	if card_parent:
		card_parent.remove_child(card)
	card.queue_free()
	selected_card = null
	_update_player_status_display()
	_update_hand_playable()
	_check_battle_end()


## 多段之间的那口气。和敌人出手用同一个数（FighterAnim.hit_beat），
## 同一场战斗里两种节奏必须一致。
func _beat() -> void:
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(FighterAnim.hit_beat()).timeout


## 玩家出手的那一下前冲（朝右，敌人在右边）。不等它。
func _swing_at_enemies() -> void:
	if player != null:
		player.strike_at_enemies()


## 多段结算期间把「结束回合」和药水一起锁上。药水也锁是因为它绕过卡牌直接结算伤害，
## 放进来一样会和正在跑的节拍交错。这一对开关和 EnemyTurnState 进出时做的是同一件事。
func _begin_resolve() -> void:
	_resolving = true
	if end_turn_button:
		end_turn_button.disabled = true
	set_potions_active(false)


func _end_resolve() -> void:
	_resolving = false
	# 只在玩家回合里放开：结算中间这一场要是打完了、状态切走，那个按钮本来就不该再能按。
	if state_machine != null and state_machine.get_current_state_name() == "PlayerTurn":
		if end_turn_button:
			end_turn_button.disabled = false
		set_potions_active(true)

func _on_end_turn_pressed() -> void:
	# 键盘那条路绕不过 disabled 的按钮，得在这儿再挡一道。
	if _resolving:
		return
	if state_machine and state_machine.get_current_state_name() == "PlayerTurn":
		state_machine.transition_to("EnemyTurn")

func _on_draw_pile_pressed() -> void:
	_open_pile(card_pile.draw_pile, "抽牌堆")


func _on_discard_pile_pressed() -> void:
	_open_pile(card_pile.discard_pile, "弃牌堆")


func _on_exhaust_pile_pressed() -> void:
	_open_pile(card_pile.exhaust_pile, "消耗堆")


## 三个牌堆都从这里开查看器，省得各写一份。交给 RunHud 挂到弹窗层上，不自己往
## 场景根节点加——根节点是第 0 层，会被 95 的横条盖住，关闭按钮又正好在右上角，
## 被横条那排按钮压着点不着，人就出不来了。
func _open_pile(cards: Array[CardData], title: String) -> void:
	var run_hud: RunHud = GameManager.run_hud
	if run_hud == null or not is_instance_valid(run_hud):
		return
	run_hud.open_card_view(cards, title)

func _on_energy_changed(current: int, _max: int) -> void:
	if energy_display_label:
		# 底栏拆散之后这枚数字单独站在左下角，光一个「3 / 3」认不出是什么，带上「能量」两个字。
		energy_display_label.text = "能量 %d / %d" % [current, energy_system.max_energy + energy_system.permanent_energy]
	_update_hand_playable()

func _update_hand_playable() -> void:
	for child in hand_container.get_children():
		if child is Card:
			# 诅咒牌永远是灰的：它和「能量不够」共用同一个置灰状态，
			# 玩家一眼就知道这张打不出去，不用先点一下再看没反应。
			child.set_playable(not child.card_data.unplayable
					and energy_system.can_spend(child.card_data.get_display_cost(player)))
			child.refresh_display(player)
	refresh_play_keys()


## 手牌右上角那排快选数字。角标位置按手牌顺序排，跟数字键一一对应。
## 牌一进出手牌就得重刷，否则编号会跳号（出了第 2 张，第 3 张还标着 3）。
##
## **公开**，因为设定页也要调它：在战斗里把「显示快速选牌按键」一改，得当场把角标
## 亮起来/收掉，不能等下一回合的能量变化顺带刷（和 [[refresh_unit_motion]] 同一个道理）。
func refresh_play_keys() -> void:
	var index := 0
	for child in hand_container.get_children():
		if not (child is Card):
			continue
		var card := child as Card
		var show: bool = SettingsManager.show_play_keys and index < PLAY_KEY_LABELS.size()
		card.set_play_key(PLAY_KEY_LABELS[index] if show else "")
		index += 1

func _update_pile_counts() -> void:
	if draw_pile_button:
		draw_pile_button.text = "抽牌堆: %d" % card_pile.get_draw_pile_size()
	if discard_pile_button:
		discard_pile_button.text = "弃牌堆: %d" % card_pile.get_discard_pile_size()
	if exhaust_pile_button:
		exhaust_pile_button.text = "消耗堆: %d" % card_pile.exhaust_pile.size()

func _on_enemy_defeated(enemy: Node) -> void:
	# 唯一的击杀事件出口。注意 enemies 不会移除死掉的敌人，所以不能用 enemies.size() 当击杀数。
	var enemy_node := enemy as EnemyBase
	if enemy_node and enemy_node.enemy_data:
		GameManager.run_enemies_killed += 1
		if enemy_node.enemy_data.tier == EnemyData.EnemyTier.BOSS:
			GameManager.run_bosses_killed += 1
	_check_battle_end()

func _process(_delta: float) -> void:
	_safety_check_timer += _delta
	if _safety_check_timer >= 2.0:
		_safety_check_timer = 0.0
		_check_battle_end()
func _check_battle_end() -> void:
	if not is_inside_tree():
		return
	if state_machine and state_machine.get_current_state_name() == "End":
		return

	var all_dead := true
	for enemy in enemies:
		if enemy.is_alive:
			all_dead = false
			break

	if all_dead and enemies.size() > 0:
		state_machine.transition_to("End", {"result": "victory"})
	elif not player.is_alive():
		state_machine.transition_to("End", {"result": "defeat"})

func get_alive_enemies() -> Array[EnemyBase]:
	var alive: Array[EnemyBase] = []
	for enemy in enemies:
		if enemy.is_alive:
			alive.append(enemy)
	return alive
