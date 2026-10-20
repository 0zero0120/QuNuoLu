extends Node

signal battle_started(enemy_group: Array)
signal battle_ended(won: bool)
signal turn_started(turn_number: int)
## 每场战斗的**第 1 个玩家回合**，在能量 reset、turn_started 都发完之后再发。
## 和 turn_started 分开是因为「首回合一次性」的遗物（铜锣）不该自己去数回合号——
## 数错了就会在第二场战斗里接着响，或者第一场之后彻底哑掉。
signal first_turn_started(turn_number: int)
signal turn_ended
signal card_played(card: CardData, target: Variant)
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal card_exhausted(card: CardData)
signal energy_changed(current: int, maximum: int)
signal damage_dealt(target: Node, amount: int, damage_type: int)
signal block_gained(target: Node, amount: int)
## 头顶那个伤害数字专用。和 damage_dealt 分开是因为那个信号的 amount 是**格挡前**的数，
## 而且遗物在听它——改它的含义会连带影响遗物触发。
## dot_type 说明这一下是不是持续伤害、是哪一种（StatusEffect.Type.POISON / BURN，
## -1 = 普通打击）。只给表现层用：数字换个颜色、音效换一个。
signal damage_number_requested(target: Node, hp_damage: int, blocked: int, dot_type: int)
## 中毒/灼烧跳了一下。单独立一条是因为它和「挨了一记」是两回事——没有打击感、该是另一个声音。
signal dot_ticked(target: Node, dot_type: int)
signal player_hp_changed(current: int, maximum: int)
signal enemy_defeated(enemy: Node)
signal enemy_intent_changed(enemy: Node, intent: IntentResource)
signal map_generated(layers: Array)
signal map_node_entered(node: MapNodeData)
signal floor_changed(new_floor: int)
signal relic_obtained(relic: RelicData)
## 充能遗物每触发一次就掉一档。横条上那排遗物要跟着重画，不然 tooltip 里的
## 「剩余 N 次」会一直停在拿到手时的数。
signal relic_charges_changed(relic_id: String, remaining: int)
signal gold_changed(new_amount: int)
signal potion_obtained(potion: PotionData)
signal potion_used(potion: PotionData, slot_index: int)
signal card_added_to_deck(card: CardData)
signal card_removed_from_deck(card: CardData)
signal card_upgraded(card: CardData)
signal run_started
signal run_won
signal run_lost
signal rest_site_entered
