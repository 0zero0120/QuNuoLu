extends Node

## 全局字号倍率。设定页勾了「字体更大」之后，界面上写死的字号统一放大。
##
## 项目里没有统一主题，字号是逐处写死的（代码里 add_theme_font_size_override、
## 场景里 theme_override_font_sizes），所以改一个地方不会全变。这里的办法是：
## 谁带着自己的字号覆盖进树，就当场按倍率放大，并把**原值**记进 meta——
## 记原值是为了幂等，同一行被反复处理时是拿原值重算，而不是在原值上再乘一遍。

const META_KEY: String = "ui_font_scale_base"
## 记我们上次写进去的值。判断「控件自己动过字号没有」要拿它比：
## 只拿基准比的话，倍率调回 1.0 时基准会被当成「控件自己改的」而锁死，字号再也缩不回去。
const META_APPLIED: String = "ui_font_scale_last"
const FONT_SIZE_KEY: String = "font_size"

## 引擎默认字号。开局先记下来，免得反复乘在自己刚改过的值上。
var _fallback_base: int = 16


func _ready() -> void:
	_fallback_base = ThemeDB.fallback_font_size
	get_tree().node_added.connect(_on_node_added)
	refresh()


## 设置变了之后调它：已经摆出来的界面也要跟着变，不能只管以后新加的控件。
func refresh() -> void:
	ThemeDB.fallback_font_size = maxi(1, roundi(float(_fallback_base) * SettingsManager.font_scale()))
	_scan(get_tree().root)


## 新控件进树时当场处理。顺带扫一遍子树：一次 add_child 带进来的整棵子树也得跟上。
func _on_node_added(node: Node) -> void:
	for child in node.get_children():
		_scan(child)
	_apply(node)


func _scan(node: Node) -> void:
	_apply(node)
	for child in node.get_children():
		_scan(child)


## 只处理**自己带字号覆盖**的控件。没有覆盖的走引擎默认值，那些由
## ThemeDB.fallback_font_size 统一管；两边都动会互相盖掉。
func _apply(node: Node) -> void:
	if not (node is Control):
		return
	var control := node as Control
	if not control.has_theme_font_size_override(FONT_SIZE_KEY):
		return

	var current := control.get_theme_font_size(FONT_SIZE_KEY)
	var base := current if not control.has_meta(META_KEY) else int(control.get_meta(META_KEY))
	var applied := current if not control.has_meta(META_APPLIED) else int(control.get_meta(META_APPLIED))
	# 当前值既不是基准、也不是我们上次写的那个 → 是控件自己改了字号（图标那种按尺寸算出来的）。
	# 那就把新值当成新基准，否则它会被头一次记下的旧基准锁住，越改越对不上。
	if current != applied:
		base = current

	var scaled := _scaled(base)
	if current != scaled:
		control.add_theme_font_size_override(FONT_SIZE_KEY, scaled)
	control.set_meta(META_KEY, base)
	control.set_meta(META_APPLIED, scaled)


func _scaled(base: int) -> int:
	return maxi(1, roundi(float(base) * SettingsManager.font_scale()))
