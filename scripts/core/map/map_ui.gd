class_name MapUI
extends Control

@export var node_button_scene: PackedScene

var map_manager: MapManager
var node_buttons: Dictionary = {}
var _canvas_size: Vector2 = Vector2(800, 2400)

## 浮层模式：对局中按 M 打开这张地图时置真。只能在**进树之前**设好——
## MapUI 是在 _ready() 里读它决定「能走还是只能看」的。
## 开着的时候点节点不走人、看牌组不响应，左下角多一个「返回」。
var overlay_mode: bool = false

## 浮层模式下点「返回」时发出来。关掉浮层的活儿归浮层自己干，
## 这里只管说一声——地图页本身（楼层之间那张）用不到它。
signal close_requested

const NODE_SPACING_X: float = 160.0
const NODE_SPACING_Y: float = 130.0
const MARGIN: float = 80.0
## 画布宽要撑满视口，但要给竖滚动条留出这点宽——不留的话内容宽正好等于容器宽，
## 竖条一出现就把容器挤窄，横滚动条跟着冒出来。
const SCROLLBAR_ALLOWANCE: float = 24.0
const EDGE_SCROLL_SPEED: float = 400.0
const EDGE_SCROLL_THRESHOLD: float = 60.0

@onready var _scroll_container: ScrollContainer = get_parent()


func _ready() -> void:
	# 这个脚本挂在 MapContent 上（MapScrollContainer 的子节点），不是场景根。
	# owner 才是场景根 MapScene——就是那块全屏 Background 所在的地方。
	# map_view_overlay 也拿 map_scene.tscn 实例化，owner 同样是它自己的实例根，两边都对。
	UIBackground.apply(owner, "map")
	map_manager = MapManager.new()
	add_child(map_manager)
	if GameManager.has_map_state():
		map_manager.restore_from(GameManager.get_map_state())
	else:
		map_manager.generate_new_map()
		# 新生成的地图立刻记一份。少了这一句，第 1 层的战斗里 has_map_state() 是假的（M 按了没反应），
		# 而且这一层的存档里 "map" 存的是空的，读回来会重新生成一张跟原来不一样的地图。
		GameManager.save_map_state(map_manager.layers, map_manager.player_current_node.node_id)
		# 顺手落盘：刚翻章时玩家还没迈出第一步，磁盘上那份存档里 map 还是空的。
		# 落盘之后再退出，读回来就是眼前这张图，而不是靠随机流碰巧重现出来的同一张。
		GameManager.save_run()
	render_map()
	call_deferred("_scroll_to_player")
	_setup_corner_buttons()


func _process(delta: float) -> void:
	_edge_scroll(delta)


## 地图上原来只有「查看牌组」这一个快捷键，现在它归全局层了（看的是这一局整副牌组），
## 这里不再接任何快捷键。


## 左侧中间那个「返回」。只在浮层模式下露出来——
## 楼层之间那张地图自己不需要它（那里的 ESC 还是暂停菜单）。
func _setup_corner_buttons() -> void:
	var corner := get_parent().get_parent()
	var return_button := corner.get_node_or_null("ReturnButton") as Button
	if return_button:
		return_button.visible = overlay_mode
		return_button.pressed.connect(func(): close_requested.emit())


func _edge_scroll(delta: float) -> void:
	if _scroll_container == null:
		return
	var mouse_pos := get_global_mouse_position()
	var vp_rect := get_viewport().get_visible_rect()
	if not vp_rect.has_point(mouse_pos):
		return

	var h := _scroll_container.scroll_horizontal
	var v := _scroll_container.scroll_vertical

	if mouse_pos.x > vp_rect.size.x - EDGE_SCROLL_THRESHOLD:
		h += EDGE_SCROLL_SPEED * delta
	elif mouse_pos.x < EDGE_SCROLL_THRESHOLD:
		h -= EDGE_SCROLL_SPEED * delta

	if mouse_pos.y > vp_rect.size.y - EDGE_SCROLL_THRESHOLD:
		v += EDGE_SCROLL_SPEED * delta
	elif mouse_pos.y < EDGE_SCROLL_THRESHOLD:
		v -= EDGE_SCROLL_SPEED * delta

	var h_max := _scroll_container.get_h_scroll_bar().max_value
	var v_max := _scroll_container.get_v_scroll_bar().max_value
	_scroll_container.scroll_horizontal = clampf(h, 0.0, h_max)
	_scroll_container.scroll_vertical = clampf(v, 0.0, v_max)


func render_map() -> void:
	_clear()
	_calculate_canvas_size()
	_calculate_positions()
	_create_node_buttons()
	queue_redraw()
	_grab_initial_focus()


## 方向键走引擎自带的按钮焦点导航，不自己算邻居：不可达的节点在 _update_visual_states() 里
## 已经把 focus_mode 关掉了，关掉焦点的控件引擎不给焦点，于是上下左右天然只在能走的节点之间挪。
## 这里给个起点，回车就通。浮层模式下按钮没接 pressed，焦点挪来挪去只是挪视角，不会走人。
func _grab_initial_focus() -> void:
	if map_manager == null:
		return
	var target: Button = null
	for node in node_buttons:
		var btn: Button = node_buttons[node]
		if btn.focus_mode != Control.FOCUS_NONE and map_manager.can_move_to(node):
			target = btn
			break
	if target == null and map_manager.player_current_node:
		# 一个能走的地方都没有（比如这条路已经到头了）。玩家脚下那个节点是「已走过」的，
		# 也已经不可聚焦——那就索性不给焦点，硬 grab 只会让引擎打一行警告。
		var here: Button = node_buttons.get(map_manager.player_current_node)
		if here != null and here.focus_mode != Control.FOCUS_NONE:
			target = here
	if target:
		target.grab_focus()


func _calculate_canvas_size() -> void:
	var total_layers := map_manager.layers.size()
	var max_nodes := 1
	for layer in map_manager.layers:
		if layer.nodes.size() > max_nodes:
			max_nodes = layer.nodes.size()

	# 横向至少撑满**滚动区**那么宽。只按「最大节点数 × 间距」算的话，三列的地图宽只有 800，
	# 在 1920 的屏上就成了「节点全挤在左边一条、右边一大片空」——_calculate_positions()
	# 是拿这个宽当可用宽度铺节点的，画布多宽节点就铺多宽，所以这里给到滚动区宽就自动铺满并居中。
	#
	# 量的是滚动区不是视口：右边留了图例面板，滚动区已经不到整屏宽了。拿视口宽算的话
	# 画布会比滚动区还宽，横滚动条就冒出来了。
	var area_width := _scroll_container.size.x
	var needed_width := MARGIN * 2.0 + (max_nodes + 1) * NODE_SPACING_X
	_canvas_size.x = maxf(area_width - SCROLLBAR_ALLOWANCE, needed_width)
	_canvas_size.y = MARGIN * 2 + (total_layers - 1) * NODE_SPACING_Y
	custom_minimum_size = _canvas_size


func _clear() -> void:
	for btn in node_buttons.values():
		btn.queue_free()
	node_buttons.clear()


func _calculate_positions() -> void:
	var usable_width := _canvas_size.x - MARGIN * 2
	var usable_height := _canvas_size.y - MARGIN * 2
	var start_x := MARGIN
	var start_y := MARGIN
	var total_layers := map_manager.layers.size()

	for i in range(total_layers):
		var layer: MapGenerator.MapLayer = map_manager.layers[i]
		var y := start_y + (float(i) / float(maxi(1, total_layers - 1))) * usable_height
		var node_count := layer.nodes.size()
		for j in range(node_count):
			var x := start_x + (float(j + 1) / float(node_count + 1)) * usable_width
			layer.nodes[j].position = Vector2(x, y)


## 连线画成**毛笔提按的墨线**：中段粗、两端细，收笔有锋；整条走一道微弧，不是死直线。
## 底色从深蓝换成了浅宣纸，所以线也得跟着换「墨」的口径——未走的用淡墨，已走的用朱砂。
## 只用 draw_line 画不出这些（它只有等宽），所以自己采成一条「宽度随 t 变化」的带子，
## 交给 draw_colored_polygon：先铺一层宽而淡的**晕**（模拟墨在纸上洇开），再压一条实的芯。
func _draw() -> void:
	if map_manager == null or map_manager.layers.is_empty():
		return

	# 同一张图上每对 (a,b) 的鼓包方向必须每次都一样，否则每帧重绘都在抖。
	# 用坐标算个确定性的哈希，别用 randf。
	for layer in map_manager.layers:
		for node in layer.nodes:
			for connected in node.connections:
				var visited: bool = node.visited and connected.visited
				var core: Color = Color(0.62, 0.2, 0.12, 0.8) if visited else Color(0.3, 0.26, 0.21, 0.6)
				var halo: Color = Color(0.62, 0.2, 0.12, 0.14) if visited else Color(0.34, 0.3, 0.25, 0.1)
				var a: Vector2 = node.position
				var b: Vector2 = connected.position
				var normal: Vector2 = Vector2(-(b - a).normalized().y, (b - a).normalized().x)
				var bow: float = minf(a.distance_to(b) * 0.075, 14.0) * _bow_sign(a, b)
				var ctrl: Vector2 = a + (b - a) * 0.5 + normal * bow
				draw_colored_polygon(_stroke_band(a, ctrl, b, 7.6), halo)
				draw_colored_polygon(_stroke_band(a, ctrl, b, 3.4), core)


## 每对端点固定鼓向同一边——坐标算的哈希，跨帧稳定。
func _bow_sign(a: Vector2, b: Vector2) -> float:
	var h: int = int(a.x) * 73856093 ^ int(a.y) * 19349663 ^ int(b.x) * 83492791 ^ int(b.y) * 26699411
	return -1.0 if (h & 1) == 0 else 1.0


## 把二次贝塞尔采成一条带状多边形：沿法线左右各偏移半个笔宽，正着走一遍再反着走回来。
## 笔宽走 sin 曲线——两端收到笔尖、中段最肥，就是毛笔按下再提起的那个「提按」。
func _stroke_band(a: Vector2, ctrl: Vector2, b: Vector2, half_max: float) -> PackedVector2Array:
	const SEG: int = 20
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var p := _quad(a, ctrl, b, t)
		var d := _quad_tangent(a, ctrl, b, t)
		if d.length_squared() < 1e-6:
			d = b - a
		var n := Vector2(-d.normalized().y, d.normalized().x)
		var w := half_max * (0.12 + 0.88 * pow(sin(PI * t), 0.6))
		left.append(p + n * w)
		right.append(p - n * w)
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly


func _quad(a: Vector2, ctrl: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * ctrl + t * t * b


func _quad_tangent(a: Vector2, ctrl: Vector2, b: Vector2, t: float) -> Vector2:
	return 2.0 * (1.0 - t) * (ctrl - a) + 2.0 * t * (b - ctrl)


func _create_node_buttons() -> void:
	if node_button_scene == null:
		return

	for layer in map_manager.layers:
		for node in layer.nodes:
			var btn: Button = node_button_scene.instantiate()
			# 按卡面自己的尺寸居中：node.position 是**中心**（连线也画在它上面），
			# 而 node_button_scene 是个直接挂在 Control 下的按钮、摆的是左上角。
			# 之前这里写死 30 = 卡面边长 60 的一半，卡面一改成 72 就偏了 6px。
			btn.position = node.position - btn.custom_minimum_size * 0.5
			# 有国风图标就用图标（引擎自带的 Button.icon + expand_icon 把 256px 缩进 60px 槽），
			# 没有才退回原来那个 emoji 字符。_update_visual_states() 靠 modulate 做的
			# 「已走过变灰 / 可达变亮」对图标一样生效。
			var icon_tex := ArtIcons.load_or_null(node.get_type_icon_path())
			if icon_tex != null:
				btn.icon = icon_tex
				btn.expand_icon = true
				btn.text = ""
			else:
				btn.text = node.get_type_icon()
			btn.tooltip_text = node.get_type_name()
			# 浮层模式下只看不走：按钮照旧按可达性显示明暗，但不接 pressed。
			if not overlay_mode:
				btn.pressed.connect(_on_node_pressed.bind(node))
			add_child(btn)
			node_buttons[node] = btn

	_update_visual_states()


## 「能走 / 不能走」两个样子，外加「能不能被方向键选到」。
## disabled 只管鼠标点不动，**管不住方向键**——引擎的焦点导航只看 focus_mode，
## 一个 disabled 的按钮照样会被上下左右选中、回车还打不出去（实测 Godot 4.6 如此）。
## 所以两样都要设：disabled 挡鼠标，focus_mode 挡方向键。
##
## 分档口径跟着底图走：底图从深蓝换成了浅宣纸，**不能再靠「调暗」表示不能走**——
## 暗色压在浅纸上不是「弱」而是「脏」。改成按**亮度**分三档：可达最亮（白卡 + 墨框），
## 已走过偏暖地压一档（那是你走过的路，还得认得出来），不可达再压一档、偏冷。
##
## **三档都必须保持 alpha = 1**：浅纸上把 alpha 降下去 = 直接消失（试过 0.24，整张图只剩
## 三张当前可走的卡，其余全没了）。弱要靠「暗一点」表达，不能靠「透明」。
func _update_visual_states() -> void:
	for node in node_buttons:
		var btn: Button = node_buttons[node]
		if node.visited:
			# 已走过：暖褐卡。走过的地方要有「落定」的颜色，不能跟没走的糊成一样。
			btn.modulate = Color(0.92, 0.86, 0.74, 1.0)
			btn.disabled = true
			btn.focus_mode = Control.FOCUS_NONE
		elif map_manager.can_move_to(node):
			btn.modulate = Color.WHITE
			btn.disabled = false
			btn.focus_mode = Control.FOCUS_ALL
		else:
			# 还没走到：把卡面压到差不多等于纸色，只剩那圈墨框——「有路，但还远」。
			# 压得比纸还暗会变成一块脏印子，反而更抢眼。
			btn.modulate = Color(0.8, 0.79, 0.78, 1.0)
			btn.disabled = true
			btn.focus_mode = Control.FOCUS_NONE


func _scroll_to_player() -> void:
	# 这里是 call_deferred 进来的，可能赶在地图场景被换掉之后才执行。
	# 那时节点已经不在树上，get_viewport() 返回 null，直接取用会报错。
	if _scroll_container == null or not is_inside_tree():
		return
	if map_manager == null or map_manager.player_current_node == null:
		return
	var player_node_pos := map_manager.player_current_node.position
	var vp_size := get_viewport().get_visible_rect().size
	var target_h := player_node_pos.x - vp_size.x / 2.0
	var target_v := player_node_pos.y - vp_size.y / 2.0
	var h_max := _scroll_container.get_h_scroll_bar().max_value
	var v_max := _scroll_container.get_v_scroll_bar().max_value
	_scroll_container.scroll_horizontal = clampf(target_h, 0.0, h_max)
	_scroll_container.scroll_vertical = clampf(target_v, 0.0, v_max)


func _on_node_pressed(node: MapNodeData) -> void:
	map_manager.move_player_to_node(node)
