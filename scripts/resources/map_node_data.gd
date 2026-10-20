class_name MapNodeData
extends RefCounted

## 存档里存的是 int，所以新类型只能往尾部追加，插在中间会让旧档的类型整体错位。
## ALTAR（诅咒祭坛）就是照这条追加的：界面上走着 EventScreen，只是抽的是祭坛那个池子。
enum NodeType { START, BATTLE, ELITE, BOSS, SHOP, REST, EVENT, CHEST, ALTAR }

var node_id: String = ""
var node_type: NodeType = NodeType.BATTLE
var floor: int = 0
var position_index: int = 0
var position: Vector2 = Vector2.ZERO
var connections: Array[MapNodeData] = []
var connected_from: Array[MapNodeData] = []
var visited: bool = false
var reachable: bool = false

func get_type_name() -> String:
	match node_type:
		NodeType.START: return "起点"
		NodeType.BATTLE: return "战斗"
		NodeType.ELITE: return "精英"
		NodeType.BOSS: return "首领"
		NodeType.SHOP: return "商店"
		NodeType.REST: return "休息"
		NodeType.EVENT: return "事件"
		NodeType.CHEST: return "宝箱"
		NodeType.ALTAR: return "祭坛"
	return "未知"

func get_type_icon() -> String:
	match node_type:
		NodeType.START: return "★"
		NodeType.BATTLE: return "⚔"
		NodeType.ELITE: return "💀"
		NodeType.BOSS: return "👑"
		NodeType.SHOP: return "💰"
		NodeType.REST: return "🏕"
		NodeType.EVENT: return "❓"
		NodeType.CHEST: return "🎁"
		NodeType.ALTAR: return "🕯"
	return "?"

const ICON_DIR := "res://assets/art/map_nodes/"

## 节点图标按 **NodeType 名的小写**推路径（START→start、BOSS→boss…），
## 跟出图那边的 mapnode_<小写名>、落位名 <小写名>.png 是同一条约定。
## **不另写一张 id→文件名 的对照表**：那份表会跟 enum 脱钩（enum 尾部追加一项它不会跟着变，
## 而这里是从 NodeType.keys() 现取的）。图不在也返回路径，由 map_ui.gd 探到取不到、
## 退回原来的 emoji——缺图不是错误状态（口径同 card_data.get_art_path()）。
func get_type_icon_path() -> String:
	var names := NodeType.keys()
	if node_type < 0 or node_type >= names.size():
		return ""
	return ICON_DIR + str(names[node_type]).to_lower() + ".png"

func to_dict() -> Dictionary:
	var conn_ids: Array[String] = []
	for c in connections:
		conn_ids.append(c.node_id)
	return {
		"node_id": node_id,
		"node_type": int(node_type),
		"floor": floor,
		"position_index": position_index,
		"visited": visited,
		"connections": conn_ids,
	}

static func from_dict(data: Dictionary) -> MapNodeData:
	var n := MapNodeData.new()
	n.node_id = str(data.get("node_id", ""))
	n.node_type = int(data.get("node_type", 0))
	n.floor = int(data.get("floor", 0))
	n.position_index = int(data.get("position_index", 0))
	n.visited = bool(data.get("visited", false))
	return n
