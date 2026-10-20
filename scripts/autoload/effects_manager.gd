extends Node

## 头顶伤害数字的颜色。金色是实际扣的血，蓝色是被格挡吃掉的那部分。
const DAMAGE_NUMBER_COLOR := Color(1.0, 0.85, 0.2)
const BLOCK_NUMBER_COLOR := Color(0.45, 0.75, 1.0)
## 持续伤害另配两种颜色：中毒墨绿、灼烧橙红。不然「毒掉的血」和「挨一刀掉的血」
## 在头顶长得一模一样，玩家读不出自己是被打了还是被毒了。
const POISON_NUMBER_COLOR := Color(0.55, 0.90, 0.45)
const BURN_NUMBER_COLOR := Color(1.00, 0.55, 0.25)
## 两个数字同时飘会叠在一起，蓝色往旁边让开半个身位。
const BLOCK_NUMBER_OFFSET := Vector2(52.0, 0.0)

var _streams: Dictionary = {}
## 打击音效的多个采样轮着放。每一下都用同一段会听腻，轮换比随机更不会连着撞。
var _hit_streams: Array[AudioStream] = []
var _hit_index: int = 0
var _audio_pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _last_player_hp: int = -1
var _number_scene: PackedScene = null
## 顿帧的世代号。新的顿帧只重开不叠加，靠它把旧的恢复计时器作废，见 hitstop。
var _hitstop_token: int = 0

func _ready() -> void:
	_build_sounds()
	_connect_signals()

func _build_sounds() -> void:
	_streams["card"] = _sound("card", _make_tone(520.0, 0.09, 0.35, "sine"))
	_streams["hit"] = _sound("hit", _make_tone(180.0, 0.12, 0.5, "noise"))
	_streams["block"] = _sound("block", _make_tone(360.0, 0.14, 0.4, "sine"))
	_streams["hurt"] = _sound("hurt", _make_tone(140.0, 0.18, 0.5, "saw"))
	_streams["enemy_death"] = _sound("enemy_death", _make_tone(110.0, 0.35, 0.5, "noise"))
	_streams["coin"] = _sound("coin", _make_tone(880.0, 0.1, 0.3, "square"))
	_streams["potion"] = _sound("potion", _make_tone(500.0, 0.18, 0.4, "sine"))
	_streams["relic"] = _sound("relic", _make_tone(660.0, 0.22, 0.4, "sine"))
	_streams["dot"] = _sound("dot", _make_tone(260.0, 0.22, 0.28, "noise"))
	_streams["victory"] = _sound("victory", _make_arpeggio([440.0, 550.0, 660.0, 880.0], 0.12))
	_streams["defeat"] = _sound("defeat", _make_arpeggio([330.0, 262.0, 196.0], 0.16))

	# 打击音是分层合成的新素材（低频体 + 中频脆响 + 极短起手），三段轮换。
	# 文件缺失时退回 _streams["hit"]（原来的单声噪声），不影响出声。
	for i in range(1, 4):
		var variant := AudioClips.load_sfx_or_null("hit_%d" % i)
		if variant != null:
			_hit_streams.append(variant)
	if _hit_streams.is_empty() and _streams.has("hit"):
		_hit_streams.append(_streams["hit"])

	for i in range(8):
		var p := AudioStreamPlayer.new()
		# 走单独的 SFX 总线，「音效音量」滑条才管得着（主音量管所有总线）。
		p.bus = SettingsManager.SFX_BUS
		add_child(p)
		_audio_pool.append(p)


## 有音频文件就播文件，没有就退回合成。跟 potion_button.gd 的「国风图先上、缺图退回
## 程序像素画」是同一套口径，共用口是 AudioClips。
##
## 合成那条路**一个字都不动**——它是兜底，缺素材时游戏照旧有声。
## 返回类型写 `AudioStream` 而不是 `AudioStreamWAV`：文件若是 ogg/mp3，写死类型会崩。
func _sound(key: String, fallback: AudioStreamWAV) -> AudioStream:
	var from_file := AudioClips.load_sfx_or_null(key)
	return from_file if from_file != null else fallback

func _connect_signals() -> void:
	EventBus.card_played.connect(func(_c, _t): _play("card"))
	EventBus.damage_dealt.connect(func(target, amount, _t): _on_damage_dealt(target, amount))
	EventBus.block_gained.connect(func(_t, _a): _play("block"))
	EventBus.enemy_defeated.connect(func(enemy): _on_enemy_defeated(enemy))
	EventBus.battle_ended.connect(func(won): _play("victory" if won else "defeat"))
	EventBus.gold_changed.connect(func(_a): _play("coin"))
	EventBus.potion_used.connect(func(_p, _s): _play("potion"))
	EventBus.relic_obtained.connect(func(_r): _play("relic"))
	EventBus.player_hp_changed.connect(_on_player_hp_changed)
	EventBus.battle_started.connect(func(_g): _last_player_hp = -1)
	EventBus.damage_number_requested.connect(_on_damage_number_requested)
	EventBus.dot_ticked.connect(func(_t, _k): _play("dot"))
	# 顿帧改的是全局的 Engine.time_scale，战斗一结束必须兜底放回去——
	# 少了这一行，任何一次「战斗在顿帧里结束」都会把整个游戏冻死。
	EventBus.battle_ended.connect(func(_won): _reset_hitstop())

func _on_damage_dealt(target: Node, amount: int) -> void:
	_play_hit(amount)
	# 粒子往**击退方向**（敌人一律朝右）扇出去，不再是四散的火花：
	# 有方向才有「被这一下推开了」的读感，数量也跟着伤害涨。
	_burst(target, Color(1.0, 0.85, 0.3), clampi(6 + amount, 8, 28), Vector2.RIGHT, 70.0)

## 挨打时头顶飘的数字。两个开关各管一种，关了那种就不飘。
## 持续伤害走的还是金色那一个开关（它就是「扣了多少血」），只是换一身颜色。
##
## 打击感（顿帧 + 刀光）也挂在这儿：玩家打敌人、敌人打玩家两个方向都发这个信号，
## 一处接完全对称，不用在两边各写一遍（[[feedback-consistent-implementation]]）。
## 只认普通打击（dot_type < 0）——中毒灼烧是「从里面烂掉」，没有挨一下的那种冲击。
func _on_damage_number_requested(target: Node, hp_damage: int, blocked: int,
		dot_type: int = -1) -> void:
	if hp_damage > 0 and SettingsManager.damage_number_gold:
		_spawn_number(target, hp_damage, _hit_color(dot_type), Vector2.ZERO)
	if blocked > 0 and SettingsManager.damage_number_blue:
		_spawn_number(target, blocked, BLOCK_NUMBER_COLOR, BLOCK_NUMBER_OFFSET)
	if hp_damage <= 0 or dot_type >= 0 or not SettingsManager.battle_motion:
		return
	hitstop(clampf(0.03 + float(hp_damage) * 0.006, 0.03, 0.09))
	_slash(target)


func _hit_color(dot_type: int) -> Color:
	match dot_type:
		StatusEffect.Type.POISON: return POISON_NUMBER_COLOR
		StatusEffect.Type.BURN: return BURN_NUMBER_COLOR
	return DAMAGE_NUMBER_COLOR

## 数字挂在**目标的父节点**上，不挂目标自己：敌人被打死时自身会淡出并往上飘，
## 挂上去的数字会被一起带走，那一下就看不见了。
func _spawn_number(target: Node, value: int, color: Color, offset: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	var host: Node = target.get_parent()
	if host == null:
		host = target
	if _number_scene == null:
		_number_scene = load("res://scenes/battle/floating_number.tscn")
	if _number_scene == null:
		return
	var number: FloatingNumber = _number_scene.instantiate()
	host.add_child(number)
	number.show_at(_target_center(target) + offset, str(value), color)


func _target_center(target: Node) -> Vector2:
	if target is Control:
		return (target as Control).global_position + (target as Control).size / 2.0
	if target is Node2D:
		return (target as Node2D).global_position
	return Vector2.ZERO


func _on_enemy_defeated(enemy: Node) -> void:
	_play("enemy_death")
	_burst(enemy, Color(0.9, 0.3, 0.25), 24)
	shake(9.0)

func _on_player_hp_changed(current: int, _maximum: int) -> void:
	if _last_player_hp >= 0 and current < _last_player_hp:
		_play("hurt")
		shake(7.0)
	_last_player_hp = current

## 打击音吃伤害：小刀轻、重锤沉。基线下压 5dB，给其他音效留位置；
## 音高 ±4% 是为了避免连续多段攻击听成复读机——超过这个数就听出走调了。
func _play_hit(amount: int) -> void:
	if _hit_streams.is_empty():
		return
	var p := _take_player()
	p.stream = _hit_streams[_hit_index]
	_hit_index = (_hit_index + 1) % _hit_streams.size()
	p.pitch_scale = randf_range(0.96, 1.04)
	p.volume_db = clampf(-5.0 + (float(amount) - 6.0) * 0.45, -7.0, 0.0)
	p.play()


func _play(name: String) -> void:
	if not _streams.has(name):
		return
	var p := _take_player()
	p.stream = _streams[name]
	# 池子是共用的，上一位留下的变调/音量必须清掉，不然「重击」的 +3dB 会漏给下一声金币。
	p.pitch_scale = 1.0
	p.volume_db = 0.0
	p.play()


func _take_player() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = _audio_pool[_pool_index]
	_pool_index = (_pool_index + 1) % _audio_pool.size()
	return p

func _burst(at_node: Node, color: Color, count: int,
		dir := Vector2.UP, spread := 180.0) -> void:
	if not SettingsManager.particles:
		return
	if at_node == null or not is_instance_valid(at_node):
		return
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = dir
	particles.spread = spread
	particles.gravity = Vector2(0, 320)
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 240.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	particles.color = color
	particles.finished.connect(particles.queue_free)
	at_node.add_child(particles)
	particles.emitting = true

## 一次普通命中该震多重。**吃伤害数值**：以前只有敌人死亡和玩家掉血各一档写死的强度，
## 小刀和重锤震得一样，反而是「不疼」的来源。抽出来单独一个函数是为了能直接断言
## 「伤害越大震得越狠」，不用去猜屏幕被推了多少像素。
static func shake_for_damage(dmg: int) -> float:
	return clampf(2.5 + float(dmg) * 0.30, 2.5, 11.0)


func shake(intensity: float = 8.0) -> void:
	if not SettingsManager.screen_shake:
		return
	var scene := get_tree().current_scene
	if scene == null or not (scene is Control):
		return
	var ctrl: Control = scene as Control
	var tween := create_tween()
	var steps := 10
	for i in range(steps):
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(ctrl, "position", offset, 0.025)
	tween.tween_property(ctrl, "position", Vector2.ZERO, 0.025)


## 命中那一下丢一片水墨刀光。挂点在**战斗场景**上，不挂挨打的那个单位——
## 敌人被打死时会整个淡出，挂在它身上等于刀光陪葬，那一下什么都看不见。
func _slash(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	var at := _target_center(target)
	# target 和场景可能不在同一个坐标系里（场景是 Control，单位挂在 Node2D 底下），
	# 直接拿 global_position 当局部坐标会差一个场景自身的位移。换算一次。
	if scene is CanvasItem and scene != target:
		at = (scene as CanvasItem).get_global_transform().affine_inverse() * at
	SlashVFX.spawn(scene, at, deg_to_rad(randf_range(-55.0, -25.0)))


## 顿帧：命中那一下把整个世界冻住几十毫秒再放开。打击感里最有效的一味——
## 数字、粒子、震屏都在动，唯独时间停了，玩家会读成「这一下结结实实打实了」。
##
## ⚠️ 改的是 `Engine.time_scale`，**全局**的。所以四条纪律：
##   1. 时长必须短（几十毫秒），跟着伤害走但硬夹在 0.03~0.09；
##   2. 恢复用 **ignore_time_scale 的计时器**，否则连计时器一起冻住，永远回不来；
##   3. 重入只**重开**不叠加（token 世代号），多段攻击不会越冻越久；
##   4. 战斗结束兜底复位（_connect_signals 里接了 battle_ended）。
func hitstop(sec: float) -> void:
	if sec <= 0.0 or not SettingsManager.battle_motion:
		return
	var tree := get_tree()
	if tree == null:
		return
	Engine.time_scale = 0.0
	_hitstop_token += 1
	var token := _hitstop_token
	var timer := tree.create_timer(sec, true, false, true)
	timer.timeout.connect(func():
		if token == _hitstop_token:
			_reset_hitstop())


func _reset_hitstop() -> void:
	Engine.time_scale = 1.0
	_hitstop_token += 1

func _make_tone(freq: float, duration: float, volume: float, kind: String) -> AudioStreamWAV:
	var rate := 22050
	var n := int(duration * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var s: float
		match kind:
			"sine":
				s = sin(TAU * freq * t)
			"square":
				s = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
			"saw":
				s = 2.0 * (t * freq - floor(t * freq + 0.5))
			_:
				s = randf() * 2.0 - 1.0
		var env := 1.0 - float(i) / float(n)
		s *= volume * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_arpeggio(freqs: Array[float], note_dur: float) -> AudioStreamWAV:
	var rate := 22050
	var per_note := int(note_dur * rate)
	var total := per_note * freqs.size()
	var data := PackedByteArray()
	data.resize(total * 2)
	for idx in range(freqs.size()):
		var freq: float = freqs[idx]
		for i in range(per_note):
			var t := float(i) / float(rate)
			var local_env := 1.0 - float(i) / float(per_note)
			var s := sin(TAU * freq * t) * 0.4 * local_env
			data.encode_s16((idx * per_note + i) * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
