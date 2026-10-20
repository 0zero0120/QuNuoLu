class_name EventData
extends Resource

@export var event_id: String = ""
@export var title: String = "事件"
@export var text: String = ""
## 内联 sub_resource 写成 Array[EventOption]，跟 EnemyData.normal_intent_pattern 同一套做法：
## 编辑器里能可视化编辑，字段也带类型。
@export var options: Array[EventOption] = []

## 这条事件归哪个池子。事件节点抽 "general"，诅咒祭坛节点抽 "altar"——同一个界面、
## 同一套动作，只是货源不同，所以用字段分池而不是另做一个祭坛界面。
## 取值有白名单断言盯着（见 _ui_frame_test.gd 的 EVENT_POOLS），拼错会当场报红。
@export var pool: String = "general"
