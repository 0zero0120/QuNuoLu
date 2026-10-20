class_name FloatingNumber
extends Label

## 挨打时头顶飘的那个数字。边升边淡出，完事自己删掉。
##
## 尺寸不靠布局算：调用方一挂上来就要摆位置，那时候布局还没跑过，量出来的尺寸是 0。
## 所以写死一块固定大小，位置按它推。

const BOX_SIZE := Vector2(120.0, 40.0)
## 从目标位置再往上抬一点，免得数字压在人物身上。
const HEAD_OFFSET := Vector2(0.0, -34.0)
const RISE := 56.0
const DURATION: float = 0.7


func show_at(center: Vector2, value_text: String, color: Color) -> void:
	text = value_text
	add_theme_color_override("font_color", color)
	size = BOX_SIZE
	global_position = center + HEAD_OFFSET - BOX_SIZE / 2.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position:y", global_position.y - RISE, DURATION)
	tween.tween_property(self, "modulate:a", 0.0, DURATION)
	tween.finished.connect(queue_free)
