class_name AccentHalo
extends RefCounted

## 立绘底下那层本角色的流派色光晕。
##
## 为什么颜色不进立绘：立绘是模型画的纯黑白水墨。试过让模型「只染配饰不染整件袍子」，
## 连着几轮都压不住——颜色总会漏到整件衣裳上，或者干脆把国风的形制顶掉。
## 所以颜色改在引擎里叠：立绘四周是透明的，光晕从透明处透出来，
## 墨色的人影压在光晕上面，看上去就是墨画洇在有色宣纸上。
##
## 敌人不叠——这是「本角色的流派色」，敌人没有流派。

## 正中间的浓度。再高人影的边缘就开始被染色，墨色会变浑。
const CENTER_ALPHA := 0.32


## 中间是 accent、往外淡出的径向渐变。径向渐变天生中间亮、边缘淡，
## 不会像叠一块半透明色矩形那样在边界上留一道硬边（跟 battle_manager 的章节补光同源）。
static func make_texture(accent: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(accent.r, accent.g, accent.b, CENTER_ALPHA))
	grad.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	# 默认 64x64 铺到几百像素上会看出色带，跟章节补光一样抬到 512。
	tex.width = 512
	tex.height = 512
	return tex


## 一块光晕。定位由调用方负责：立绘是铺满 rect 的，光晕也照抄同一个 rect，
## 按短边适配成一枚正圆。
static func make_rect(accent: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "AccentHalo"
	rect.texture = make_texture(accent)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
