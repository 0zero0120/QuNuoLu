class_name PauseOverlay
extends ColorRect

func _ready() -> void:
	var vbox := $PausePanel/PauseVBox
	vbox.get_node("ResumeButton").pressed.connect(_on_resume)
	vbox.get_node("ReturnMenuButton").pressed.connect(_on_return_menu)
	vbox.get_node("QuitButton").pressed.connect(_on_quit)

func open() -> void:
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _on_resume() -> void:
	close()

func _on_return_menu() -> void:
	get_tree().paused = false
	# 战斗打到一半不存盘：磁盘上留着进战斗前那一份，重进才能回到这场战斗的开局。
	# 存了的话玩家当前的残血会一起落盘，回来就是「退出时的状态」，不是开局。
	# 战斗结束后 EndState 会把标志清掉，那时照常存。
	# 商店/休息/事件是另一套：内容进去就锁死、每次操作都已经实时存过了，
	# 这里再存一次也是同一份，所以照常存。
	if not GameManager.pending_is_battle():
		GameManager.save_run()
	GameManager.change_screen(GameManager.GameScreen.MAIN_MENU)

func _on_quit() -> void:
	get_tree().quit()
