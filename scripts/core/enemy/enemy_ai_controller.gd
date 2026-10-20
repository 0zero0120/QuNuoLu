class_name EnemyAIController
extends Node

signal intent_determined(intent: IntentResource)

enum AIState { NORMAL, AGGRESSIVE }

## 收益树的权重。所有分支都折算成「这一招值多少点伤害」，攻击就是基准——
## 以前减益/增益/格挡的系数只有 3~8，而攻击直接就是伤害（6~22），
## 于是数据里躺着的减益、增益、格挡意图永远选不上，15 只敌人全是每回合平砍。
const DEFEND_LOW_HP_WEIGHT: float = 1.5   # 血越少格挡越值钱，残血时最多翻到 2.5 倍（满血 1.0 倍）
const BUFF_TURNS_LEFT: float = 3.0         # 增益按「这场架还剩约 3 回合」折算
## 激怒（仪式）用的是更长的回收期。它不是「这一回合的一次加成」，是每回合都白送一份、
## 之后每一击都多打一份、下一回合还会再拿一次——滚的是整场架剩下的回合数。
## 按 3 回合算的话一层仪式只值 6 分，连格挡（12 分）都压不过，数据里填了也没人选。
const RITUAL_TURNS_LEFT: float = 5.0
const VULNERABLE_WEIGHT: float = 0.5       # 易伤期间每一下多挨 50%，就是它值的那部分
const WEAK_WEIGHT: float = 0.25            # 虚弱让玩家每回合少打 25%
const DEBUFF_BASE: float = 0.4             # 玩家残血时减益只值四成——马上要打死他了，挂了也白挂
const DEBUFF_FULL_HP_BONUS: float = 0.6    # 玩家满血时回本时间最长，系数加到 1.0
const REPEAT_PENALTY: float = 0.4          # 最近用过的招数按次数打这个折
const RECENT_MEMORY: int = 2               # 记最近两招，够判断「同一招连打了几轮」
## 玩家身上已经挂着同一种持续伤害时，再叠一次的折扣。见 _score_debuff 里那一段。
const DOT_REAPPLY_FACTOR: float = 0.3
const SUMMON_TURNS_LEFT: float = 3.0       # 召唤出来的帮手按「这场架还剩约 3 回合」折算
## 一张打不出去的废牌值多少。**故意按「平砍」的量级填，而不是按它真实的伤害当量**：
## 死牌的真实代价大概只有几点伤害（少抽一张有用的），照着填的话它永远排在平砍（14~22）
## 和格挡（12）后面，数据里写了的怪一次也不会掏出来，塞诅咒就成了死内容。
## 填到 30 是让它压过最重的一拳、但靠着重复折扣（用过一次只剩 12）退回来，
## 于是节奏变成「塞一张 → 砍两下 → 再塞一张」。
const CURSE_CARD_VALUE: float = 30.0

var enemy_data: EnemyData
var current_state: AIState = AIState.NORMAL

## 最近出过的招（按顺序，保留 RECENT_MEMORY 条）。同一招每在里面出现一次就多打一次折：
## 出现过一次 ×0.4、连着两轮还出 ×0.16。只按「上一轮」罚的话，池子里只有一张攻击牌的
## 敌人（兔小那种 [攻击,攻击,虚弱]）靠攻击分高还是能连着硬打，减益永远轮不上。
var _recent_intents: Array[IntentResource] = []

## 脚本化轮转走到第几条。只有 scripted_intents 的敌人用它，换阶段时归零。
var _script_index: int = 0

func setup(data: EnemyData) -> void:
	enemy_data = data
	_recent_intents.clear()
	_script_index = 0

# 行为收益树入口：对意图池中每个行为计算收益，选择收益最高者执行。
func get_next_intent(player: Player) -> IntentResource:
	check_phase_transition()
	var pool := _get_current_pool()
	if pool.is_empty():
		return null
	if enemy_data.scripted_intents:
		return _next_scripted(pool)

	var best: IntentResource = pool[0]
	var best_score: float = -INF
	for intent in pool:
		var score := _evaluate_intent(intent, player) * _repeat_penalty(intent)
		if score > best_score:
			best_score = score
			best = intent

	# 记在「算出意图」这一刻，不是执行那一刻——意图是锁定的，执行时不再重算。
	# 阶段切换会在同一回合里再算一次，那次也照记：换阶段本来就是换了套招。
	_recent_intents.append(best)
	if _recent_intents.size() > RECENT_MEMORY:
		_recent_intents.pop_front()

	intent_determined.emit(best)
	return best


## 脚本化出招：池子照顺序走、到底回头，不看收益分也不打重复折扣。
## 蓄力怪要的就是固定节拍——「蓄 3 回合 → 放一次大招」，是定数不是概率。
## 池子最后一条是那一发大招，倒计时按「离池尾还有几条」推出来，写进敌人的 CHARGE 状态。
## 倒计时绝不能写进 intent.value：_scale_intents 会按章数乘 value，第 2、3 章的倒计时要跟着涨。
func _next_scripted(pool: Array[IntentResource]) -> IntentResource:
	var index := _script_index % pool.size()
	var intent := pool[index]
	_script_index += 1
	var enemy := get_parent() as EnemyBase
	if enemy != null:
		enemy.set_charge_countdown(pool.size() - 1 - index)
	intent_determined.emit(intent)
	return intent

## 返回「这一次调用是不是刚好翻到激进阶段」。翻阶段是怪物特性：进了二阶段要立刻换一套意图池，
## 所以打完一段伤害血量过线时，EnemyBase 会拿这个 true 去重算并刷新头顶图标。
## 没填激进池的敌人永远不会翻，行为跟以前一样。
func check_phase_transition() -> bool:
	if current_state == AIState.AGGRESSIVE:
		return false
	if enemy_data.aggressive_intent_pattern.is_empty():
		return false
	var enemy := get_parent()
	if enemy is EnemyBase:
		var hp_ratio := float(enemy.current_hp) / float(enemy_data.max_hp)
		if hp_ratio <= enemy_data.hp_threshold:
			current_state = AIState.AGGRESSIVE
			# 换阶段 = 换套招，轮转从头数起：蓄力怪的二阶段该重新蓄一轮，
			# 而不是接着上一轮的进度条直接放大招。
			_script_index = 0
			return true
	return false

func _get_current_pool() -> Array[IntentResource]:
	if current_state == AIState.AGGRESSIVE and not enemy_data.aggressive_intent_pattern.is_empty():
		return enemy_data.aggressive_intent_pattern
	return enemy_data.normal_intent_pattern

## 自己一拳最重能打多少。减益值多少、力量值多少，都拿它当尺子——
## 22 攻的凶兽远比 6 攻的小怪看重易伤。
func _best_attack_damage() -> float:
	var enemy := get_parent() as EnemyBase
	var best := 0.0
	for intent in _get_current_pool():
		if intent.intent_type in [IntentResource.IntentType.ATTACK, IntentResource.IntentType.SPECIAL]:
			best = maxf(best, float(intent.total_damage() + enemy.strength))
	return best

## 自己一回合大概能格挡多少。敏捷值多少就拿它当尺子——没有格挡牌的敌人加敏捷是白加。
func _best_block_value() -> float:
	var enemy := get_parent() as EnemyBase
	var best := 0.0
	for intent in _get_current_pool():
		if intent.intent_type == IntentResource.IntentType.DEFEND:
			best = maxf(best, float(intent.value * intent.multiplier + enemy.dexterity))
	return best

func _repeat_penalty(intent: IntentResource) -> float:
	var used := 0
	for recent in _recent_intents:
		if recent == intent:
			used += 1
	return pow(REPEAT_PENALTY, used)

# ---- 行为收益评估节点 ----
func _evaluate_intent(intent: IntentResource, player: Player) -> float:
	match intent.intent_type:
		IntentResource.IntentType.ATTACK, IntentResource.IntentType.SPECIAL:
			return _score_attack(intent, player)
		IntentResource.IntentType.DEFEND:
			return _score_defend(intent, player)
		IntentResource.IntentType.BUFF:
			return _score_buff(intent, player)
		IntentResource.IntentType.DEBUFF:
			return _score_debuff(intent, player)
		IntentResource.IntentType.SUMMON:
			return _score_summon(intent)
		IntentResource.IntentType.CURSE:
			return _score_curse(intent)
		_:
			return 0.0

## 多段攻击按总值算：3 段 ×6 就是一拳 18，比 6 值钱。格挡只减一次是粗略算法
## （实际每段各吃一次，能被挡得更多），对「挑哪一招」的判断足够了。
func _score_attack(intent: IntentResource, player: Player) -> float:
	var enemy := get_parent() as EnemyBase
	var dmg := intent.total_damage() + enemy.strength
	if enemy.has_status_of_type(StatusEffect.Type.WEAK):
		dmg = int(ceil(float(dmg) * 0.75))
	if player.has_status_of_type(StatusEffect.Type.VULNERABLE):
		dmg = int(ceil(float(dmg) * 1.5))
	var actual := maxi(0, dmg - player.current_block)
	var score := float(actual)
	if actual >= player.current_hp:
		score += 100.0
	return score

func _score_defend(intent: IntentResource, _player: Player) -> float:
	var enemy := get_parent() as EnemyBase
	var block := intent.value * intent.multiplier + enemy.dexterity
	var hp_ratio := float(enemy.current_hp) / float(enemy_data.max_hp)
	return float(block) * (1.0 + (1.0 - hp_ratio) * DEFEND_LOW_HP_WEIGHT)

func _score_buff(intent: IntentResource, _player: Player) -> float:
	var gain := intent.value * intent.multiplier
	# 增益是滚雪球的：+1 力量在之后每一击上都多打 1 点，+1 敏捷在之后每次格挡上都多挡 1 点。
	# 池子里没有对应的动作就一点也不值——不会格挡的敌人加敏捷纯属浪费回合。
	match intent.status_effect_type:
		StatusEffect.Type.STRENGTH:
			if _best_attack_damage() <= 0.0:
				return 0.0
		StatusEffect.Type.DEXTERITY:
			if _best_block_value() <= 0.0:
				return 0.0
		StatusEffect.Type.RITUAL:
			# 激怒/仪式是滚雪球里的滚雪球：每回合白拿一份力量，拿了之后每一击都多打一份，
			# 下一回合还会再拿。折成「剩下这几回合总共多打出来的伤害」就是 1+2+…+n 份
			# （n = RITUAL_TURNS_LEFT），比一次性 +力量 值钱得多。不这么算它的分永远压不过
			# 平砍，数据里填了也没人选，机制就成死内容了。
			# 重复折扣会自然把它压回一回合一次：连出两轮的话第二轮的 15 分只剩 2.4。
			if _best_attack_damage() <= 0.0:
				return 0.0
			return float(gain) * RITUAL_TURNS_LEFT * (RITUAL_TURNS_LEFT + 1.0) * 0.5
	return float(gain) * BUFF_TURNS_LEFT

func _score_debuff(intent: IntentResource, player: Player) -> float:
	var stacks := intent.value * intent.multiplier
	# 玩家越满血，减益越有回本的时间；残血玩家马上就被打死了，挂了也白挂。
	var hp_ratio := float(player.current_hp) / float(player.max_hp)
	var time_factor := DEBUFF_BASE + DEBUFF_FULL_HP_BONUS * hp_ratio

	# 中毒/灼烧是固定真伤，不吃 _best_attack_damage 那根尺子：不会攻击的敌人下毒照样疼。
	# N 层在之后每回合扣 N、N-1、…，合计 N(N+1)/2 点，而且无视格挡——这是它比平砍值钱的地方。
	if StatusEffect.is_dot(intent.status_effect_type):
		var total := float(stacks) * (float(stacks) + 1.0) * 0.5
		# 第一条毒是「起」，后面都是「续」——两者价值差着一截，不能按同一个口径算。
		# 起一条 N 层的毒，玩家之后每回合挨 N、N-1、…，总共 N(N+1)/2 点；可玩家身上已经挂着
		# 同一种毒时，那几层本来就在扣血，再叠 N 层只是每回合**多**扣 N 点，没有第一手那种
		# 一路滚下来的加成。不折这一下的话毒永远压过平砍（毒 5 层 = 15 分 vs 平砍 6 分），
		# 怪就每回合无脑续毒、层数滚到二十几，玩家挂再多格挡也接不住——试玩日志里真发生过。
		if player.get_status_value(intent.status_effect_type) > 0:
			total *= DOT_REAPPLY_FACTOR
		return total * time_factor

	var per_stack := VULNERABLE_WEIGHT
	if intent.status_effect_type == StatusEffect.Type.WEAK:
		per_stack = WEAK_WEIGHT
	return _best_attack_damage() * per_stack * float(stacks) * time_factor

## 召唤值多少：叫出来的帮手不是打一下就走，是在这场架剩下的回合里一直打，所以按
## 「援兵一拳 × 预计剩余回合 × 实际能叫出来的只数」折。
## 位子满了、次数用完了、叫的那只不在敌人库里，一律值 0——那种时候召唤就是白扔一个回合，
## AI 该去挑池子里别的招。
func _score_summon(intent: IntentResource) -> float:
	var enemy := get_parent() as EnemyBase
	if enemy == null or not enemy.can_summon():
		return 0.0
	var data := DataManager.get_enemy(enemy_data.summon_enemy_id)
	if data == null:
		return 0.0
	var count: int = mini(mini(intent.value * intent.multiplier, enemy_data.summon_count),
			enemy.free_slots())
	if count <= 0:
		return 0.0
	return float(count) * _best_attack_damage_of(data) * SUMMON_TURNS_LEFT


## 别的敌人一拳最重能打多少。援兵的值按它自己的池子算，不是按召唤者自己的
## ——叫出来的可能是完全另一种怪。
func _best_attack_damage_of(data: EnemyData) -> float:
	var best := 0.0
	for intent in data.normal_intent_pattern:
		if intent != null and intent.intent_type in [IntentResource.IntentType.ATTACK,
				IntentResource.IntentType.SPECIAL]:
			best = maxf(best, float(intent.total_damage()))
	return best


## 塞诅咒值多少：塞进去的是一张打不出去的废牌，烂在手里等于让玩家每一次抽牌都少一张有用的。
## 分值为什么比它的实际伤害当量高得多，见 CURSE_CARD_VALUE 那段——目标是让它和平砍交替
## 出现：分给高了怪就只会一直塞牌不打人，分给低了数据里填了也永远选不上。
func _score_curse(intent: IntentResource) -> float:
	var count := intent.value * intent.multiplier
	if count <= 0 or intent.insert_card_id.is_empty():
		return 0.0
	return float(count) * CURSE_CARD_VALUE


func reset() -> void:
	current_state = AIState.NORMAL
	_recent_intents.clear()
	_script_index = 0
