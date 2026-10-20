class_name PaperDoll
extends RefCounted

## 皮影立绘：把**一张整图**按水平缝切成几段，每段绕**自己的底边中点**转。
##
## 为什么要这样：上一版的所有动作都是「整张立绘刚性平移」（改 sprite.position / unit.scale），
## 玩家一眼就看穿了——「人物抽搐了一下」「是整幅画在上下动，不是人本身在动」。
## 想让立绘像个人，就得让**身体各部位各自动**：头转、上身甩、下盘稳。
## 没有逐帧素材、也没上骨骼，那就用皮影的老办法——把画剪成几片，钉在关节上转。
##
## 几何前提（都是量过的）：立绘源图 512x768，立绘槽 180x270，**长宽比都是 2:3**。
## 所以纵向按比例切，横向同一系数，切完拼回去和原图逐像素一致，不会变形。
##
## 缝的位置按「颈 / 腰 / 膝」取，别的不动：改这个数组就等于改关节在哪。
##
## 每段都向上向下各多切一点（OVERLAP_PX）当**搭接**：静止时两段的重叠区画的是同样的像素，
## 看不出接缝；转起来的时候重叠区盖住转出来的缝，不会露白。

## 缝的位置，按整图高度的比例，必须从 0.0 到 1.0 严格递增。4 段 5 条缝。
## 用普通 Array 而不是 PackedFloat32Array：GDScript 的 const 只认字面量表达式，
## `PackedFloat32Array([...])` 是构造调用，不算常量。
const BAND_FRACTIONS := [0.0, 0.22, 0.48, 0.72, 1.0]
## 搭接高度（画布像素）。太小转起来露缝，太大会盖掉相邻段本来的形。
const OVERLAP_PX := 8.0
## 每段的摆动权重：**越靠下越沉**。腿脚几乎不摆，否则整个人像在跳。
## 地面溅墨/衣摆这类「本来就不该动」的东西也在下段，权重低才不会被甩飞。
const SWAY_WEIGHTS := [1.0, 0.7, 0.35, 0.12]
## 源图和槽的长宽比差到多少就不切了。差太多切出来每段会被拉变形——
## 那种情况退回单张 TextureRect（KEEP_ASPECT_CENTERED 本来就负责这个）。
const ASPECT_TOLERANCE := 0.02
## 源图太矮就切不出段（每段只剩十几个像素），退回单张。
const MIN_SRC_HEIGHT := 96

## 每段子节点的名字前缀，FighterAnim 按它认段。
const PART_PREFIX := "Part"


## 这张图能不能切。不能切就走调用方那边的单张兜底。
static func supported(tex: Texture2D, slot_w: float, slot_h: float) -> bool:
	if tex == null or slot_w <= 0.0 or slot_h <= 0.0:
		return false
	var src_w := float(tex.get_width())
	var src_h := float(tex.get_height())
	if src_h < MIN_SRC_HEIGHT or src_w <= 0.0:
		return false
	var tex_aspect := src_w / src_h
	var slot_aspect := slot_w / slot_h
	return absf(tex_aspect - slot_aspect) / slot_aspect <= ASPECT_TOLERANCE


## 切好装在一个 Control 里返回。**调用方负责把这个 Control 摆到立绘槽上**
## （anchors/offset 照抄占位色块），这里只管把段拼出来。
## 段的绘制顺序 = 从上往下一层层加，最后加的（下段）画在最上面，压住搭接区。
static func build(tex: Texture2D, slot_w: float, slot_h: float) -> Control:
	var root := Control.new()
	root.name = "PaperDoll"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 位置/尺寸**写 offset 而不是只写 size**：只设 size 的话，节点一入树 Godot 会照
	# anchors + offset 重算一遍矩形，offset 还是 0 就塌成 0x0，里面各段的锚点全跟着归零。
	# （ArtSwap 随后会拿占位色块的 offset 覆盖掉这四个数，那是它的事。）
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 0.0
	root.anchor_bottom = 0.0
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = slot_w
	root.offset_bottom = slot_h

	var src_w := float(tex.get_width())
	var src_h := float(tex.get_height())
	# 源图 -> 槽 的缩放系数。长宽比已对齐（supported 把关），横向纵向同一个数。
	var k := slot_h / src_h
	var overlap_src := OVERLAP_PX / k

	for i in range(BAND_FRACTIONS.size() - 1):
		var band_top: float = float(BAND_FRACTIONS[i]) * src_h
		var band_bottom: float = float(BAND_FRACTIONS[i + 1]) * src_h
		# 上下各多切 OVERLAP_PX，靠 clamp 保证不越界。
		var region_top := maxf(0.0, band_top - overlap_src)
		var region_bottom := minf(src_h, band_bottom + overlap_src)

		var part := TextureRect.new()
		part.name = "%s%d" % [PART_PREFIX, i]
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		part.stretch_mode = TextureRect.STRETCH_SCALE
		var slice := AtlasTexture.new()
		slice.atlas = tex
		slice.region = Rect2(0.0, region_top, src_w, region_bottom - region_top)
		part.texture = slice

		# 位置用**锚点**表达「源图的哪一段」而不是写死像素：槽尺寸变了段自己跟着走。
		part.anchor_left = 0.0
		part.anchor_right = 1.0
		part.anchor_top = region_top / src_h
		part.anchor_bottom = region_bottom / src_h
		part.offset_left = 0.0
		part.offset_right = 0.0
		part.offset_top = 0.0
		part.offset_bottom = 0.0

		# 转轴是**真底边**（那条缝）的中点，不是含搭接的矩形底边——差那 8px 会让
		# 转动看起来「钉在下面一点的地方」，脖子和肩膀对不上。
		part.pivot_offset = Vector2(slot_w / 2.0, (band_bottom - region_top) * k)
		part.set_meta("pd_sway", float(SWAY_WEIGHTS[i]) if i < SWAY_WEIGHTS.size() else 1.0)
		root.add_child(part)
	return root


## 从容器里按名字把段捞回来，**按 Part 序号排好**（子节点顺序本来就是这个，
## 但显式排一次，免得以后有人往中间插了别的东西）。认不出段就返回空数组，
## 调用方据此走「单张立绘」那条老路。
static func parts_of(container: Node) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is TextureRect and String(child.name).begins_with(PART_PREFIX):
			out.append(child)
	out.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.name) < String(b.name))
	return out
