class_name CheckIcon
extends RefCounted

## 勾选框那两个状态图标，用代码画出来。
##
## 引擎默认的一对本身近黑色（不勾的那个还只有一半不透明度），本项目的面板又全是深底，
## 压上去等于看不见——没勾的项看上去就只是一行字，不知道那儿能点。
## 自己画一版：没勾的是一圈灰描边，勾上的是金色描边加对勾，深底上一眼能分出来。
##
## 先在放大四倍的画布上画、再缩回来，边缘就平滑了。不引入任何图片素材。

const SIZE: int = 18
const SUPERSAMPLE: int = 4

const BORDER_COLOR := Color(0.62, 0.64, 0.74)
const ON_COLOR := Color(0.96, 0.84, 0.42)

static var _unchecked: ImageTexture = null
static var _checked: ImageTexture = null


## 把这个勾选框的两个状态都换成看得见的版本。图标只画一次，之后共用。
static func apply(box: CheckBox) -> void:
	if box == null:
		return
	if _unchecked == null:
		_unchecked = _make(false)
	if _checked == null:
		_checked = _make(true)
	box.add_theme_icon_override("unchecked", _unchecked)
	box.add_theme_icon_override("checked", _checked)


static func unchecked_texture() -> ImageTexture:
	if _unchecked == null:
		_unchecked = _make(false)
	return _unchecked


static func checked_texture() -> ImageTexture:
	if _checked == null:
		_checked = _make(true)
	return _checked


static func _make(on: bool) -> ImageTexture:
	var side := SIZE * SUPERSAMPLE
	var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var color := ON_COLOR if on else BORDER_COLOR
	_frame(img, 2 * SUPERSAMPLE, color)
	if on:
		_tick(side, img)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


## 方框的四条边。
static func _frame(img: Image, width: int, color: Color) -> void:
	var side := img.get_width()
	_fill(img, 0, 0, side, width, color)
	_fill(img, 0, side - width, side, width, color)
	_fill(img, 0, 0, width, side, color)
	_fill(img, side - width, 0, width, side, color)


## 方框里那个对勾，两笔粗线。
static func _tick(side: int, img: Image) -> void:
	var span := float(side)
	var corner := Vector2(span * 0.26, span * 0.52)
	var elbow := Vector2(span * 0.44, span * 0.71)
	var tip := Vector2(span * 0.76, span * 0.29)
	var width := span * 0.13
	_stroke(img, corner, elbow, width)
	_stroke(img, elbow, tip, width)


## 粗线段就是沿线一路盖小方块。够用，也省得引一个画线的东西进来。
static func _stroke(img: Image, from: Vector2, to: Vector2, width: float) -> void:
	var steps := int(from.distance_to(to) * 2.0) + 1
	var radius := int(width * 0.5) + 1
	for i in range(steps + 1):
		var point := from.lerp(to, float(i) / float(steps))
		_fill(img, int(point.x) - radius, int(point.y) - radius,
			radius * 2 + 1, radius * 2 + 1, ON_COLOR)


## 画一块方色。超出画布的部分自己裁掉——Image 的填充不保证替我们裁。
static func _fill(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var x0 := maxi(0, x)
	var y0 := maxi(0, y)
	var x1 := mini(img.get_width(), x + w)
	var y1 := mini(img.get_height(), y + h)
	if x1 <= x0 or y1 <= y0:
		return
	img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), color)
