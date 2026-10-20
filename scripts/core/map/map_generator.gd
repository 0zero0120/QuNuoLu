class_name MapGenerator
extends RefCounted

class MapLayer:
	var floor: int
	var nodes: Array[MapNodeData]

	func _init(f: int) -> void:
		floor = f
		nodes = []

var config: MapConfig

func _init(p_config: MapConfig) -> void:
	config = p_config

## floor_offset：本章最底层在全局层数里的编号（见 MapConfig.first_floor_of_chapter）。
## 内部一切照旧按本地层号 0..16 走，最后整体平移一次——见 _shift_to_global 里的两个理由。
func generate(floor_offset: int = 0) -> Array[MapLayer]:
	var layers: Array[MapLayer] = []

	# Floor 0: START
	var start_layer := MapLayer.new(0)
	var start_node := MapNodeData.new()
	start_node.node_type = MapNodeData.NodeType.START
	start_node.floor = 0
	start_node.position_index = 0
	start_node.node_id = "start"
	start_layer.nodes.append(start_node)
	layers.append(start_layer)

	# Floors 1 to (total-2): Normal floors
	var boss_floor := config.total_floors - 1
	for i in range(1, boss_floor):
		var layer := _generate_floor(i)
		layers.append(layer)

	# Last floor: BOSS
	var boss_layer := MapLayer.new(boss_floor)
	var boss_node := MapNodeData.new()
	boss_node.node_type = MapNodeData.NodeType.BOSS
	boss_node.floor = boss_floor
	boss_node.position_index = 0
	boss_node.node_id = "boss"
	boss_layer.nodes.append(boss_node)
	layers.append(boss_layer)

	# Generate connections bottom-up
	_generate_connections(layers)

	# BFS validate
	if not _validate_reachability(layers):
		for lyr in layers:
			for nd in lyr.nodes:
				if nd.connections.is_empty():
					nd.connections.append(boss_node)

	_shift_to_global(layers, floor_offset)
	return layers

## 把整张图从本地层号平移到全局层号，并给每个节点 id 加上章号前缀。
## 两个都必须在所有生成逻辑跑完之后做：
##   · 层号——_distribute_types() 是拿本地层号跟 config.mid_boss_floor 比的，先平移的话
##     第 2、3 章的「中段一个精英」就永远对不上了；
##   · id——相连节点靠 id 在存档里认人（见 GameManager._deserialize_map），
##     三章的 "start" / "boss" 是同一串字，不加章号跨章会撞。
func _shift_to_global(layers: Array[MapLayer], floor_offset: int) -> void:
	var prefix := "c%d_" % config.chapter_id
	for layer in layers:
		layer.floor += floor_offset
		for node in layer.nodes:
			node.floor += floor_offset
			node.node_id = prefix + node.node_id

func _generate_floor(floor: int) -> MapLayer:
	var layer := MapLayer.new(floor)
	var count := GameManager.run_rng.randi_range(2, config.nodes_per_floor)
	var types := _distribute_types(count, floor)

	for i in range(count):
		var node := MapNodeData.new()
		node.node_type = types[i]
		node.floor = floor
		node.position_index = i
		node.node_id = "floor%d_node%d" % [floor, i]
		layer.nodes.append(node)
	return layer

func _distribute_types(count: int, floor: int) -> Array:
	var result: Array = []

	# Mid-boss: one elite
	if floor == config.mid_boss_floor:
		result.append(MapNodeData.NodeType.ELITE)
		count -= 1

	# At least one battle
	result.append(MapNodeData.NodeType.BATTLE)
	count -= 1

	# 序盘几层不出精英节点：卡组还没成型，撞上精英基本等于送。见 MapConfig.elite_first_floor。
	var elite_weight := config.elite_weight if floor >= config.elite_first_floor else 0.0
	var type_pool: Array = [
		{"type": MapNodeData.NodeType.BATTLE, "weight": config.battle_weight},
		{"type": MapNodeData.NodeType.ELITE, "weight": elite_weight},
		{"type": MapNodeData.NodeType.SHOP, "weight": config.shop_weight},
		{"type": MapNodeData.NodeType.REST, "weight": config.rest_weight},
		{"type": MapNodeData.NodeType.EVENT, "weight": config.event_weight},
		{"type": MapNodeData.NodeType.CHEST, "weight": config.chest_weight},
		{"type": MapNodeData.NodeType.ALTAR, "weight": config.altar_weight},
	]

	for _i in range(maxi(0, count)):
		var total_weight: float = 0.0
		for entry in type_pool:
			total_weight += entry["weight"]
		var roll := GameManager.run_rng.randf() * total_weight
		var cumulative: float = 0.0
		var chosen := MapNodeData.NodeType.BATTLE
		for entry in type_pool:
			cumulative += entry["weight"]
			if roll <= cumulative:
				chosen = entry["type"]
				break
		result.append(chosen)

	GameManager.rand_shuffle(result)
	return result

func _generate_connections(layers: Array[MapLayer]) -> void:
	for i in range(layers.size() - 1):
		var current := layers[i].nodes
		var next := layers[i + 1].nodes
		var cn := current.size()
		var nn := next.size()

		if cn == 0 or nn == 0:
			continue

		# Bottom-up monotonic: each next-layer node connects to a 1–2 node
		# window in the current layer, with windows advancing left to right
		# so lines never cross.
		var cur_pos := 0
		for j in range(nn):
			var next_node := next[j]
			var span_size := GameManager.run_rng.randi_range(1, mini(2, cn - cur_pos))
			var end_idx := mini(cur_pos + span_size, cn)
			for k in range(cur_pos, end_idx):
				var cur_node := current[k]
				cur_node.connections.append(next_node)
				next_node.connected_from.append(cur_node)
			if end_idx > cur_pos:
				cur_pos = end_idx - 1  # allow window overlap by 1

		# Ensure trailing current nodes connect to the last next node
		var last_next := next[nn - 1]
		for k in range(cur_pos + 1, cn):
			if not last_next in current[k].connections:
				current[k].connections.append(last_next)
				last_next.connected_from.append(current[k])

func _validate_reachability(layers: Array[MapLayer]) -> bool:
	var start := layers[0].nodes[0]
	var boss := layers[layers.size() - 1].nodes[0]
	var visited: Array[MapNodeData] = []
	var queue: Array[MapNodeData] = [start]

	while not queue.is_empty():
		var current: MapNodeData = queue.pop_front()
		if current == boss:
			return true
		if visited.has(current):
			continue
		visited.append(current)
		for neighbor in current.connections:
			if not visited.has(neighbor):
				queue.append(neighbor)
	return false
