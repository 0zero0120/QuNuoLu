class_name AscensionText
extends RefCounted
## 难度的显示文案。级数本体是 1..10 的整数，只有给人看的字在这里拼。
##
## 数字用大写繁体（壹貳參…）：难度的第一档不加任何敌人加成、等同于普通对局，
## 叫「难度 壹」比「进阶 1」更贴实情。

const PREFIX: String = "难度"

const NUMERALS: Array[String] = [
	"壹", "貳", "參", "肆", "伍", "陸", "柒", "捌", "玖", "拾",
]


## 超出 1..10 就退回阿拉伯数字：正常玩不到（上限是 balance.tres 的 max_ascension），
## 但显示层不该因为这个崩或者显示空白。
static func numeral(level: int) -> String:
	if level >= 1 and level <= NUMERALS.size():
		return NUMERALS[level - 1]
	return str(level)


static func label(level: int) -> String:
	return "%s %s" % [PREFIX, numeral(level)]
