class_name FighterAnim
extends RefCounted

## 战斗单位的动态效果：待机摇摆/呼吸、受击后仰、出手前冲、抬手。
## Player 和 EnemyBase 共用这一份，**同一种方式实现同类功能**——两边的战斗立绘长得一样、
## 反应也该一样，没有理由是两套代码。
##
## **动作不是「整幅画平移」，是「人本身在动」**：立绘被 PaperDoll 切成几段（皮影），
## 待机时各段绕自己的底边各转各的、带滞后地甩。这是「身体在动」和「一张画在动」的区别，
## 上一版就是栽在只做刚性平移上（「人物抽搐了一下」「整幅画上下动」）。
##
## **关键设计：每种动作占一个互不重叠的属性**，各条 tween 因此不会互相打断：
##
##   待机摇摆        → 各段(part).rotation        ← 皮影，本文件里唯一写 part 属性的地方
##   待机浮动        → sprite.position:y
##   待机呼吸        → root.scale
##   受击后退 / 出手前冲 → sprite.position:x
##   受击后仰 / 出手前倾 → sprite.rotation
##   出手压扁拉伸    → sprite.scale
##   受击闪白        → sprite.modulate
##
## root 的 `modulate`（玩家指目标时的敌人高亮，见 player_turn_state）和
## `modulate:a` + `position:y`（敌人的死亡淡出，见 enemy_base）**另有其人，这里一概不碰**——
## 往角色身上挂新动画之前，先回来看一眼这张表，别去抢已经有人占着的属性。
##
## ⚠️ 待机浮动写 `position:y`、受击位移写 `position:x`，是同一条属性的两个子路径。
## Godot 的 PropertyTweener 走 set_indexed 只写命中的那个分量，理论上是各写各的；
## 但这属于「按文档推算」，实际有没有互相打断要在带窗口里看动图确认（别只信注释）。

## 多段攻击每一段之间的节拍（秒）。玩家出牌和敌人出手共用这一个数——
## 「一段一段蹦」的手感两边必须一样，否则同一场战斗里两种节奏打架。
const HIT_BEAT: float = 0.11
## 从起手到「冲到最前」的时长，也就是动作和命中对齐的那一刻。= 蓄力 + 前冲。
const STRIKE_CONTACT: float = 0.18

## 出手各段的时长。**不受加速模式影响**（见 _dur 上面的说明）。
const STRIKE_CHARGE: float = 0.07
const STRIKE_LUNGE: float = 0.11
const STRIKE_SETTLE: float = 0.24
const FLINCH_OUT: float = 0.08
const FLINCH_BACK: float = 0.20
const GESTURE_UP: float = 0.10
const GESTURE_DOWN: float = 0.20


static func hit_beat() -> float:
	# 不变乘 anim_scale()：这是**动作**之间的节拍，不是等待。加速模式只该缩短翻牌和停顿。
	return HIT_BEAT


## 待机幅度。**必须小**：这里要的是「呼吸」，不是「整块在晃」——
## 给静态底图加全图位移那次就是栽在这上面（山树云全跟着动，玩家评价「树都在抽搐」）。
## 皮影摇摆接管了「活着」这件事之后，浮动退成一层薄薄的底噪（4px 时像整块在飘）。
const FLOAT_AMPLITUDE: float = 2.0
const FLOAT_PERIOD: float = 2.2
const BREATH_AMOUNT: float = 0.012
const BREATH_PERIOD: float = 2.6

## 皮影摇摆：周期、段与段之间的相位差（弧度）、单段最大转角。
## 相位差让动作从上往下一节一节传下去（头先动、腰跟上），是「甩」不是「整块摇」。
const SWAY_PERIOD: float = 2.4
const SWAY_LAG: float = 0.42
const SWAY_MAX_ANGLE_DEG: float = 2.2

## 后仰 / 前倾的角度（度）。**跟位移一样是「身体在动」的主力**：
## 只推 6px 像被蹭了一下，绕着脚底倾 2.5° 才是挨了一记。
const LEAN_FLINCH_DEG: float = 2.0
const LEAN_STRIKE_DEG: float = 2.8
const LEAN_CHARGE_DEG: float = 1.2
const LEAN_GESTURE_DEG: float = 1.5

## 受击后退 / 出手前冲的距离（像素）。皮影上线后这两个数**退居次要**（主力是角度），
## 所以比上一版小：位移大只会更像「整幅画被推了一下」。
const FLINCH_DISTANCE: float = 6.0
const STRIKE_DISTANCE: float = 12.0

## 闪白。modulate 是**乘**上去的，>1 才是提亮；纯白 (1,1,1) 乘上去等于什么都没干。
## 偏暖一点：白纸水墨的立绘本来就亮，纯白提亮在那上面看不出来，暖白才有「挨了一下」的读感。
const FLASH_COLOR := Color(2.2, 2.0, 1.8)
const FLASH_TIME: float = 0.10

## 立的 sprite 槽在场景里写死的尺寸（offset 差）。布局还没跑过时 size 是 0，拿它兜底。
const FALLBACK_SPRITE_SIZE := Vector2(180.0, 270.0)

var _unit: Node2D = null
var _sprite_name: String = ""
var _sprite: Control = null
var _base_sprite_pos := Vector2.ZERO
var _base_sprite_scale := Vector2.ONE
var _base_sprite_rotation: float = 0.0
var _base_unit_scale := Vector2.ONE
var _base_modulate := Color.WHITE
var _captured: bool = false

var _idle_tween: Tween = null
var _breath_tween: Tween = null
var _sway_tween: Tween = null
## 这一份待机自己摇到的周期。单位之间**必须不一样**，否则整屏同相脉动；
## 留个记录也方便测试直接查「到底摇没摇」。
var _idle_period: float = 0.0
var _breath_period: float = 0.0
var _sway_period: float = 0.0
## 本单位的摇摆基准相位。和周期一样是「各单位错开」的那一半，也留给测试查。
var _sway_phase: float = 0.0
## 皮影的各段（PaperDoll 切出来的 Part*）。空数组 = 这张图切不了段，走单张老路。
var _parts: Array = []
var _move_tween: Tween = null
var _shape_tween: Tween = null
var _flash_tween: Tween = null


func attach(unit: Node2D, sprite_name: String) -> void:
	_unit = unit
	_sprite_name = sprite_name
	_unit_scale_base()


## 取到 sprite，顺带把它的「原始」值抄一份：后面所有位移/缩放/角度都是相对它算的，
## 中途改坏了也不会越跑越偏。
func _ensure_sprite() -> bool:
	if _unit == null or not is_instance_valid(_unit):
		return false
	if _sprite != null and is_instance_valid(_sprite) and _sprite.is_inside_tree():
		return true
	# 名字不会变：ArtSwap 换图时新节点照样叫 EnemySprite/PlayerSprite，旧的才改名成 …Placeholder。
	# 所以每次现查最稳（换过图、复活换过身体都不会指到已经释放的节点上）。
	_sprite = _unit.get_node_or_null(_sprite_name) as Control
	if _sprite == null:
		return false
	if not _captured:
		_base_sprite_pos = _sprite.position
		_base_sprite_scale = _sprite.scale
		_base_sprite_rotation = _sprite.rotation
		_base_modulate = _sprite.modulate
		_captured = true
	# 压扁/拉伸、后仰前倾都绕**脚底中心**转：绕左上角拽会像被人扯歪。
	# size 还没算出来就按场景里那个槽估。
	var s := _sprite.size
	if s.x <= 0.0 or s.y <= 0.0:
		s = FALLBACK_SPRITE_SIZE
	_sprite.pivot_offset = Vector2(s.x / 2.0, s.y)
	return true


## 段是 ArtSwap 换图时一次性建好的，但 start_idle 可能在换图前后被反复调用，
## 每次现捞一遍最稳（捞不到就是空数组，摇摆整段跳过）。
func _refresh_parts() -> void:
	_parts = PaperDoll.parts_of(_sprite)


func _unit_scale_base() -> void:
	if _unit != null and is_instance_valid(_unit):
		_base_unit_scale = _unit.scale


## 时长统一走这一道。**不乘 SettingsManager.anim_scale()**：
## 加速模式的开关说明写的是「把翻牌动画和敌人出手之间的停顿缩短一半」——
## 那是**等待**。角色的受击/出手/待机是**动作**，被砍半之后一次前冲只剩 88ms（约 5 帧），
## 人眼根本抓不住，真机上看起来就是「敌人没动」。动作一律全速。
func _dur(base: float) -> float:
	return base


## 动作总闸。关掉之后待机/受击/出手全不做，和「屏幕震动」「关闭粒子」一个档次。
func _enabled() -> bool:
	return SettingsManager.battle_motion


# --- 待机 ---

## 一直挂着的小幅浮动 + 呼吸 + 皮影摇摆。**每只错开**：周期本身带随机，开头再垫一段随机静默，
## 否则三只怪一起上下，整屏看着像在脉动。
func start_idle() -> void:
	stop_idle()
	if not _enabled() or not _ensure_sprite():
		return
	var period: float = FLOAT_PERIOD * randf_range(0.85, 1.2)
	var t := _unit.create_tween()
	t.tween_interval(randf() * period)
	t.tween_property(_sprite, "position:y",
			_base_sprite_pos.y - FLOAT_AMPLITUDE, period * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_sprite, "position:y", _base_sprite_pos.y, period * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.set_loops()
	_idle_tween = t
	_idle_period = period

	# 呼吸和浮动一样要各摇各的。呼吸是 scale 脉冲，幅度看着小，但在 270px 的立绘上
	# 换算下来有 3px 上下，和浮动是同一个量级——不摇相位的话整屏一起鼓，就是「整屏在脉动」。
	_unit_scale_base()
	var breathe_period: float = BREATH_PERIOD * randf_range(0.85, 1.2)
	var breathe := _unit.create_tween()
	breathe.tween_interval(randf() * breathe_period)
	breathe.tween_property(_unit, "scale", _base_unit_scale * (1.0 + BREATH_AMOUNT),
			breathe_period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(_unit, "scale", _base_unit_scale,
			breathe_period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.set_loops()
	_breath_tween = breathe
	_breath_period = breathe_period

	# 皮影摇摆。用 **tween_method 推一个 0→TAU 的角度**再在回调里取 sin()：
	# 这样一个 tween 就能同时驱动所有段，而且每段想要什么相位差就什么相位差——
	# 用普通 tween_property 的话「相位差」只能靠不同的循环长度凑，段会越走越散。
	# sin(0) == sin(TAU)，循环处接得上，不会跳。
	_refresh_parts()
	if _parts.is_empty():
		return
	_sway_phase = randf() * TAU
	_sway_period = SWAY_PERIOD * randf_range(0.85, 1.2)
	var sway := _unit.create_tween()
	sway.tween_method(_apply_sway, 0.0, TAU, _sway_period)
	sway.set_loops()
	_sway_tween = sway


## 摇摆的那一帧。角度 = sin(本单位基准相位 + 段序 * 滞后) * 该段权重。
func _apply_sway(angle: float) -> void:
	var max_rad := deg_to_rad(SWAY_MAX_ANGLE_DEG)
	for i in _parts.size():
		var part: Control = _parts[i]
		var amp: float = max_rad * float(part.get_meta("pd_sway", 1.0))
		part.rotation = sin(angle + _sway_phase + float(i) * SWAY_LAG) * amp


## 停下待机并把浮动量归零——死亡淡出那条 tween 动的是 root 的 `position:y`，
## 待机呼吸动的是 root 的 `scale`，都不跟它抢；但角色的 sit 位置得还回原样，
## 否则淡出是从「浮在半空」的位置开始飘的。各段的转角同理得归零，
## 不然死掉的那一帧人是歪的。
func stop_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
	if _breath_tween != null and _breath_tween.is_valid():
		_breath_tween.kill()
	_breath_tween = null
	if _sway_tween != null and _sway_tween.is_valid():
		_sway_tween.kill()
	_sway_tween = null
	for part in _parts:
		if part is Control and is_instance_valid(part):
			part.rotation = 0.0
	if not _captured:
		return
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.position.y = _base_sprite_pos.y
	if _unit != null and is_instance_valid(_unit):
		_unit.scale = _base_unit_scale


# --- 受击 ---

## 挨了一下。`dir` 是后退方向：敌人朝右 +1（玩家在左）、玩家朝左 -1（敌人在右）。
## `dir == 0` 只闪白不后退——持续伤害（中毒/灼烧）是「从里面烂掉」，谈不上被打飞。
##
## 后仰取**反方向**（-dir）：人被从正面推一把，脚站住了、上半身会往推力反方向甩一下。
## 顺着力推的话看起来像自己主动前倾，不是挨打。
func flinch(dir: int) -> void:
	if not _enabled() or not _ensure_sprite():
		return
	_flash()
	if dir == 0:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var lean := -deg_to_rad(LEAN_FLINCH_DEG) * float(dir)
	var t := _unit.create_tween()
	t.tween_property(_sprite, "position:x",
			_base_sprite_pos.x + FLINCH_DISTANCE * dir, _dur(FLINCH_OUT)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "rotation", _base_sprite_rotation + lean,
			_dur(FLINCH_OUT)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "position:x", _base_sprite_pos.x, _dur(FLINCH_BACK)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(_sprite, "rotation", _base_sprite_rotation,
			_dur(FLINCH_BACK)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween = t


## 只是闪一下。被完全格挡时用：盾接住了，人没退。
func flash_only() -> void:
	if not _enabled() or not _ensure_sprite():
		return
	_flash()


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.modulate = FLASH_COLOR
	_flash_tween = _unit.create_tween()
	_flash_tween.tween_property(_sprite, "modulate", _base_modulate, _dur(FLASH_TIME))


# --- 出手 ---

## 出手：先蓄力（往后一缩、压扁），再前冲（拉长、向目标扑出去、身体前倾），最后弹回原位。
## **等到「冲到最前」那一刻就返回**，调用方在那一刻结算伤害，动作和命中才对得上；
## 回位那半截让它在后台自己跑完，不等——不然敌人回合每只怪都要多等一截。
## 关掉「战斗动态效果」时是**同步返回**的，调用方的 await 会立刻通过。
func strike(dir: int) -> void:
	if not _enabled() or not _ensure_sprite():
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	if _shape_tween != null and _shape_tween.is_valid():
		_shape_tween.kill()

	var bx := _base_sprite_pos.x
	var bs := _base_sprite_scale
	var br := _base_sprite_rotation
	var charge := _dur(STRIKE_CHARGE)
	var lunge := _dur(STRIKE_LUNGE)
	var lean_fwd := deg_to_rad(LEAN_STRIKE_DEG) * float(dir)
	var lean_back := -deg_to_rad(LEAN_CHARGE_DEG) * float(dir)

	var t := _unit.create_tween()
	# 蓄力：往后缩一点、压扁（顶住那一下），上半身先向后仰
	t.tween_property(_sprite, "scale", Vector2(bs.x * 1.06, bs.y * 0.94), charge)
	t.parallel().tween_property(_sprite, "position:x", bx - STRIKE_DISTANCE * 0.25 * dir, charge)
	t.parallel().tween_property(_sprite, "rotation", br + lean_back, charge)
	# 前冲：拉长、扑向目标，身体前倾
	t.tween_property(_sprite, "scale", Vector2(bs.x * 0.95, bs.y * 1.06), lunge) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "position:x", bx + STRIKE_DISTANCE * dir, lunge) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "rotation", br + lean_fwd, lunge) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 回位（调用方不等这一段）
	t.tween_property(_sprite, "scale", bs, _dur(STRIKE_SETTLE)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "position:x", bx, _dur(STRIKE_SETTLE)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "rotation", br, _dur(STRIKE_SETTLE)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shape_tween = t
	_move_tween = t

	# 等「冲到最前」那一刻，**用计时器而不是等自己的信号**：上面那条 tween 万一被谁 kill 掉
	# （比如同一帧又挨了一下，flinch 会 kill 掉同一个 _move_tween），等信号就会永远等下去，
	# 敌人回合直接卡死。计时器的死活和 tween 无关。
	var tree := _unit.get_tree()
	if tree == null:
		return
	await tree.create_timer(_dur(STRIKE_CONTACT)).timeout


## 不出手、但「动了」的一下：防御/增益/减益/召唤/诅咒这些意图也要有动作，
## 不然敌人回合就是「站着不动、头上冒个数」。抬手——原地轻轻一顶、上半身前倾一点，不带位移。
func gesture() -> void:
	if not _enabled() or not _ensure_sprite():
		return
	if _shape_tween != null and _shape_tween.is_valid():
		_shape_tween.kill()
	var bs := _base_sprite_scale
	var br := _base_sprite_rotation
	var t := _unit.create_tween()
	t.tween_property(_sprite, "scale", Vector2(bs.x * 1.05, bs.y * 0.95), _dur(GESTURE_UP))
	t.parallel().tween_property(_sprite, "rotation", br + deg_to_rad(LEAN_GESTURE_DEG),
			_dur(GESTURE_UP))
	t.tween_property(_sprite, "scale", bs, _dur(GESTURE_DOWN)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "rotation", br, _dur(GESTURE_DOWN)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shape_tween = t
