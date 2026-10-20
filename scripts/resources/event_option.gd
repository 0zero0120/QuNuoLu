class_name EventOption
extends Resource

## 事件的一个选项。action 用字符串而不是枚举，跟 RelicData.trigger_event / effect_type
## 同一套惯例：.tres 里肉眼可读、手改得动，拼错了能被动作白名单断言抓出来。
@export var label: String = ""
@export var action: String = "nothing"
@export var value: float = 0.0

## 前置条件。凑不齐时不把按钮变灰，而是弹一句反馈、这次选择不算数，
## 玩家还能改选别的项——事件只有一次机会，变灰等于把出路堵死。
## cost_hp 是代价也是门槛：付不起（会把人扣死）就按条件不足处理。
@export var cost_hp: int = 0
@export var require_relic: String = ""
## 条件不足时的那句话。逐条写是为了让「你要先去弄个金刚杵」说得清楚，
## 留空则退回界面里的通用文案。
@export var blocked_text: String = ""

## 选完这一项之后接着摆出来的下一组选项。空着＝事件到此为止，正常收尾。
## 和 options 一样用内联 sub_resource 写，编辑器里能一层层可视化编辑。
## 一页可以有多个「继续往下」和一个「到此为止」——走到头没有是看**实际选的那条路径**
## 末端有没有下一组，不是看这一页有没有（见 EventScreen._is_finished）。
@export var next_options: Array[EventOption] = []
