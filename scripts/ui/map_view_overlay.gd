class_name MapViewOverlay
extends CanvasLayer

## 对局中随时能看的地图浮层（默认按 M）。**只读**：整张地图看得见、能滚、能用方向键挪视角，
## 但点节点不会走过去——想走人得等回到地图那一屏。
##
## 内容直接拿 scenes/map/map_scene.tscn 来用：楼层标签、图例、滚动、连线、节点排版全是现成的，
## 照着再写一份只会两边分叉。MapUI 那些 @onready 是伸手往父节点上够的，所以只能整个场景端过来。
##
## 「返回」按钮在左下角，点了和按 ESC 一样——**回到打开地图之前那个界面**，不是回主菜单。
## 打开期间整棵树是暂停的（暂停由 GameManager 开、也由它收）：底下那个界面就该冻住，
## 不然在看地图的时候按数字键还能把手牌打出去。

## 压在暂停菜单（100）下面、盖在游戏画面上面。
const LAYER: int = 90


func _ready() -> void:
	layer = LAYER
	# 整棵树是暂停的，浮层自己得照样收得到输入、底下的地图也才滚得动。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var packed: PackedScene = load("res://scenes/map/map_scene.tscn")
	if packed == null:
		return
	var scene := packed.instantiate() as Control
	var map_ui := scene.get_node_or_null("MapScrollContainer/MapContent") as MapUI
	if map_ui:
		# 必须在进树**之前**设：overlay_mode 是 MapUI 在 _ready() 里读的。
		map_ui.overlay_mode = true
		map_ui.close_requested.connect(close)
	add_child(scene)


## ESC 和 M 都用来关掉自己。走 _input（输入链第一站）：这里吃掉之后，
## 全局那个 ESC（暂停菜单）根本收不到，不会变成「关了地图又弹出暂停」。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		close()


## 「返回」按钮、ESC、M 三条路都走这里：关掉自己，回到打开之前那个界面。
func close() -> void:
	GameManager.close_map_view()
