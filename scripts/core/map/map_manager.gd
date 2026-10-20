class_name MapManager
extends Node

var config: MapConfig
var layers: Array = []
var player_current_node: MapNodeData
var generator: MapGenerator

func generate_new_map() -> void:
	config = MapConfig.new()
	config.chapter_id = GameManager.current_chapter
	generator = MapGenerator.new(config)
	layers = generator.generate(MapConfig.first_floor_of_chapter(GameManager.current_chapter))
	player_current_node = layers[0].nodes[0]
	player_current_node.visited = true
	EventBus.map_generated.emit(layers)

func restore_from(state: Dictionary) -> void:
	layers = state["layers"]
	var pid: String = state["player_node_id"]
	for layer in layers:
		for node in layer.nodes:
			if node.node_id == pid:
				player_current_node = node
				return

func move_player_to_node(node: MapNodeData) -> void:
	if not can_move_to(node):
		return
	player_current_node = node
	node.visited = true
	GameManager.current_floor = node.floor
	GameManager.current_encounter_type = node.node_type
	GameManager.visited_node_ids.append(node.node_id)
	GameManager.save_map_state(layers, node.node_id)
	# 必须在 save_run() 之前定：存档就是靠这两个字段决定读档后落在哪个屏的。
	# 战斗类存下来的是「开打前」的状态（战斗中不存盘），读档正好回到战斗开局；
	# 商店/休息/事件则由各自界面把内容快照补进 node_state，之后每次操作实时重写。
	GameManager.resume_screen = GameManager.screen_for_node_type(node.node_type)
	GameManager.node_state = {}
	GameManager.save_run()
	EventBus.map_node_entered.emit(node)

	GameManager.change_screen(GameManager.screen_for_node_type(node.node_type))

func can_move_to(node: MapNodeData) -> bool:
	if node.visited:
		return false
	return node in player_current_node.connections

func get_reachable_nodes() -> Array[MapNodeData]:
	var reachable: Array[MapNodeData] = []
	for conn in player_current_node.connections:
		if not conn.visited:
			reachable.append(conn)
	return reachable
