class_name HoldToConfirm
extends RefCounted

## 「长按确认」：把按钮的「点一下」改成「按住一会儿才算数」。
##
## 用在点错了就回不去的地方——结束回合、覆盖存档。设定页没开这个选项时直接连
## pressed，行为和原来一模一样（测试里不许真按「覆盖」造存档，靠的就是这条）。
##
## 计时器挂在按钮自己身上：按钮没了它跟着没，不用谁去收拾。

const HOLD_SECONDS: float = 0.6

## 按住期间按钮变暗。「按了没反应」和「按了正在计时」得看得出区别。
const HOLDING_COLOR := Color(0.7, 0.7, 0.78)


static func attach(button: Button, on_confirm: Callable, hold: bool) -> void:
	if button == null:
		return
	if not hold:
		button.pressed.connect(on_confirm)
		return

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = HOLD_SECONDS
	button.add_child(timer)
	timer.timeout.connect(func():
		button.modulate = Color.WHITE
		on_confirm.call())
	# 中途松手就取消。按住不放但鼠标滑出按钮时也会发 button_up，正好用得上。
	button.button_down.connect(func():
		button.modulate = HOLDING_COLOR
		timer.start())
	button.button_up.connect(func():
		button.modulate = Color.WHITE
		timer.stop())
