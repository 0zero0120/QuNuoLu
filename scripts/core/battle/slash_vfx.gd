class_name SlashVFX
extends Node2D

## 命中那一下的水墨刀光。
##
## **程序生成**，不靠素材：一条两头收尖、中间最粗的弧，近似水墨「起笔重、收笔轻」的笔触。
## 之所以不走「画一张刀光贴图」：那是又一笔要还的美术债，而这条弧只活 0.18 秒，
## 在打击感里它只是陪衬，真正让人读出「打实了」的是顿帧。
##
## 和 `EffectsManager._sound(key, fallback)` 同一套口径：**存在素材就用素材**，
## 把 `assets/art/vfx/slash.png` 丢进去就自动换成真图，代码一个字不用改。

## 有就用它，没有就程序画。
const TEXTURE_PATH := "res://assets/art/vfx/slash.png"
## 存活时长（秒）。短促是刻意的——刀光拖长了就从「斩击」变成「烟雾」。
const LIFETIME := 0.18
## 弧上取多少个采样点。太少边缘是折线，太多没必要（它只活 0.18 秒）。
const SEGMENTS := 16
## 弧的张开角 / 半径 / 最粗处的宽度（画布像素）。
const SPAN_DEG := 130.0
const RADIUS := 78.0
const THICKNESS := 26.0
## 墨色，带一点透明：压在立绘上不能糊成一块死黑，得透出底下的画。
const INK := Color(0.06, 0.06, 0.09, 0.85)

var _use_texture: bool = false


## 在 parent 下的 at 处放一片刀光，整体转 angle。**返回节点，自己会 queue_free。**
static func spawn(parent: Node, at: Vector2, angle: float) -> SlashVFX:
	if parent == null or not is_instance_valid(parent):
		return null
	var vfx := SlashVFX.new()
	vfx.position = at
	vfx.rotation = angle
	if ResourceLoader.exists(TEXTURE_PATH):
		var spr := Sprite2D.new()
		spr.texture = load(TEXTURE_PATH)
		vfx.add_child(spr)
		vfx._use_texture = true
	parent.add_child(vfx)
	vfx._play()
	return vfx


func _play() -> void:
	scale = Vector2.ONE * 0.72
	modulate.a = 0.9
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * 1.15, LIFETIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME)
	t.tween_callback(queue_free)


func _draw() -> void:
	if _use_texture:
		return
	var span := deg_to_rad(SPAN_DEG)
	var outer: Array[Vector2] = []
	var inner: Array[Vector2] = []
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var a := -span * 0.5 + span * t
		# 两头收成尖、中间最粗。开 0.7 次方让「收」来得缓一点，更像毛笔不是柳叶。
		var taper: float = pow(1.0 - absf(2.0 * t - 1.0), 0.7)
		var half := THICKNESS * 0.5 * taper
		var dir := Vector2(cos(a), sin(a))
		outer.append(dir * (RADIUS + half))
		inner.append(dir * (RADIUS - half))
	var poly := PackedVector2Array()
	for p in outer:
		poly.append(p)
	for i in range(inner.size() - 1, -1, -1):
		poly.append(inner[i])
	draw_colored_polygon(poly, INK)
