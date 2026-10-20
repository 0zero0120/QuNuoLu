class_name ArtSwap
extends RefCounted

## 把场景里那块占位色块（ColorRect）换成真立绘（TextureRect，或切好段的 PaperDoll）。
## 战斗场景里敌人的头顶方块和玩家自己的 PlayerSprite 是同一种东西，共用这一套。
##
## 为什么不是「场景里直接写成 TextureRect」：没有美术资源的角色还得有东西显示。
## 换图时旧色块只是改个名留着，没图就继续用它，不至于开天窗。
##
## 为什么新节点要照抄 anchors/offset：占位块挂在 Node2D 底下，位置全靠 anchors + offset
## 撑出来，不搬过去新节点会塌成一个点、缩在左上角。


## 换图成功返回新节点，其余情况（没图 / 还没入树 / 已经换过）返回 null。
## 换过之后旧节点叫 `<slot>Placeholder`，所以再调用一次不会叠第二张。
## accent 是本角色的流派色，传了就照占位块的定位垫一层光晕（见 AccentHalo）。
## 敌人调用时不传，所以敌人头顶没有光晕。
##
## 返回的是 **Control**，不是 TextureRect：长宽比对得上时，立绘交给 PaperDoll 切成几段
## （皮影，让身体各部位能各自转），对不上才退回单张 TextureRect。
## 两种情况下这一层都是「立绘本体」，位置/缩放/旋转/闪白都写在它身上。
static func fill(holder: Node, slot: String, tex: Texture2D,
		accent := Color(0, 0, 0, 0)) -> Control:
	if holder == null or tex == null or not holder.is_node_ready():
		return null
	if holder.has_node(slot + "Placeholder"):
		return null
	var placeholder := holder.get_node_or_null(slot) as ColorRect
	if placeholder == null:
		return null

	var slot_w := placeholder.size.x
	var slot_h := placeholder.size.y
	if slot_w <= 0.0 or slot_h <= 0.0:
		slot_w = placeholder.offset_right - placeholder.offset_left
		slot_h = placeholder.offset_bottom - placeholder.offset_top

	var sprite: Control
	if PaperDoll.supported(tex, slot_w, slot_h):
		sprite = PaperDoll.build(tex, slot_w, slot_h)
	else:
		sprite = _single_rect(tex)
	sprite.anchor_left = placeholder.anchor_left
	sprite.anchor_top = placeholder.anchor_top
	sprite.anchor_right = placeholder.anchor_right
	sprite.anchor_bottom = placeholder.anchor_bottom
	sprite.offset_left = placeholder.offset_left
	sprite.offset_top = placeholder.offset_top
	sprite.offset_right = placeholder.offset_right
	sprite.offset_bottom = placeholder.offset_bottom

	# 名字最后再改：旧的还占着 slot 这个名字，先腾出来才能给新节点。
	placeholder.name = slot + "Placeholder"
	placeholder.add_sibling(sprite)
	sprite.name = slot
	placeholder.queue_free()

	if accent.a > 0.0:
		# 照抄立绘的定位，插到它前一个位置——前面就是底下，影子一样垫着。
		var halo := AccentHalo.make_rect(accent)
		halo.anchor_left = sprite.anchor_left
		halo.anchor_top = sprite.anchor_top
		halo.anchor_right = sprite.anchor_right
		halo.anchor_bottom = sprite.anchor_bottom
		halo.offset_left = sprite.offset_left
		halo.offset_top = sprite.offset_top
		halo.offset_right = sprite.offset_right
		halo.offset_bottom = sprite.offset_bottom
		holder.add_child(halo)
		holder.move_child(halo, sprite.get_index())
	return sprite


## 一张铺满槽的 TextureRect。切不了段（长宽比对不上、源图太小）时走这条。
static func _single_rect(tex: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
