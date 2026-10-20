// 战斗章节底图的动效。三章共用这一份，差别只在 battle_manager.gd 里那几组 uniform 预设。
//
// 设计前提（这一版是推翻重做的）：这三张图是玩家已经认可的静态稿，动效必须是**纯加法**——
// 只往上叠一层雾、加一层光，画面本身一个像素都不许动。上一版做成了全图 UV 位移
// （呼吸缩放 + 横向漂移 + 高频涟漪），结果山、树、云全跟着晃，玩家原话「树都在抽搐」。
// 位移一旦作用在整幅画上，画面里所有东西都会动，这是死路。
//
// 唯一的例外是第 2 章的漩涡自转，但它是**有界摆动**：角度用 sin 限死在一个小范围里来回，
// 半径之外用 smoothstep 收干净，所以漩涡外面的山石一个像素都不动，也不会越转越偏。
//
// 所有周期都取成 10 秒的整数分之一，出 GIF 时按 10 秒扫一遍，首尾严丝合缝。
shader_type canvas_item;
render_mode unshaded;

// —— 调试/出图用 ——
// >= 0 时拿它当时间轴，忽略引擎 TIME。带窗口录 GIF 时按固定步长扫它。
uniform float time_override = -1.0;

// —— 雾（纯叠加，三章都可开）——
uniform float fog_strength : hint_range(0.0, 1.0) = 0.0;   // 0 = 这章不起雾
uniform vec3  fog_color = vec3(0.95, 0.94, 0.91);
uniform float fog_low : hint_range(0.0, 1.2) = 0.45;       // 雾带下沿：这条线以上才开始起雾
uniform float fog_high : hint_range(0.0, 1.4) = 0.95;      // 雾带上沿：这条线以下才开始收
uniform float fog_scale : hint_range(0.5, 12.0) = 6.0;     // 噪声密度：越大雾团越碎
uniform float fog_rise : hint_range(0.0, 4.0) = 1.6;       // 一层雾 10 秒里往上飘几个噪声格
uniform float fog_thr_low : hint_range(0.0, 1.0) = 0.30;   // 噪声到这条线才开始起雾
uniform float fog_thr_high : hint_range(0.0, 1.0) = 0.72;  // 到这条线雾就满——两条线拉得越开雾越成片，越窄越像丝缕

// —— 漩涡自转（第 2 章）——
uniform float swirl_strength : hint_range(0.0, 1.0) = 0.0; // 摆动幅度（弧度），不是角速度
uniform vec2  swirl_center = vec2(0.518, 0.715);
uniform float swirl_radius : hint_range(0.05, 1.0) = 0.40; // 影响半径，边界平滑收住

// —— 天光（第 3 章）——
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2  glow_center = vec2(0.5, 0.30);
uniform vec3  glow_color = vec3(1.0, 0.86, 0.62);

const float TWO_PI = 6.2831853;
const float ASPECT = 1.7777778;   // 底图 1280x720，做圆形/旋转运算时要把 x 乘回去
const float CYCLE = 0.1;          // 1/10 Hz：一个完整来回 10 秒

// 便宜的 value noise：整数格点上取哈希再双线性插值。
// 够用且不挂 NoiseTexture2D——没有异步生成、退出时资源未释放这些麻烦。
// 注意它**不**对整数位移周期（换一个格点就是另一组哈希），所以雾的无缝循环不能靠
// 「滑整数格」来做，得靠下面那套淡入淡出（见 fog 那一段）。
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.0) * 0.28 + vnoise(p * 4.0) * 0.17;
}

void fragment() {
	float t = time_override >= 0.0 ? time_override : TIME;
	vec2 uv = UV;

	// 漩涡：绕中心摆动。角度有界（±swirl_strength），半径外用 smoothstep 收干净，
	// 所以漩涡外面——山、石、云——一个像素都不动。
	if (swirl_strength > 0.0) {
		vec2 p = uv - swirl_center;
		p.x *= ASPECT;
		float falloff = 1.0 - smoothstep(0.0, swirl_radius, length(p));
		float a = swirl_strength * falloff * sin(t * CYCLE * TWO_PI);
		float s = sin(a);
		float c = cos(a);
		p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
		p.x /= ASPECT;
		uv = p + swirl_center;
	}

	vec4 tex = texture(TEXTURE, uv);
	vec3 base = tex.rgb;

	// 雾：朝雾色混过去，越靠近下沿越浓。注意混完才乘 modulate——
	// 这样战斗里的压暗对雾一样生效，雾不会变成一层比画面还亮的白斑。
	//
	// 无缝循环靠的是**两层雾、相位差半拍**：每层权重取 sin²(π·相位)，相位 0 和 1 处
	// 权重都正好是 0，正飘到看不见的时候滑回起点，接缝就藏住了；而 sin² 与 cos² 之和恒为 1，
	// 所以两层加起来浓淡恒定，不会看出「一涌一歇」的脉动。
	// 雾色可以带 >1 的 HDR 值：先混进 base 再被 modulate 压暗，最终仍比被压暗的画面亮一截，
	// 这才是第一章那种「白纸上一片白雾」唯一能看见的办法（纯 1.0 的白色压在 217 亮度的纸上等于没有）。
	if (fog_strength > 0.0) {
		// 雾带：下沿渐入、上沿渐出，让雾聚在水面那一段，而不是一路糊到画面最下边。
		float band = smoothstep(fog_low, fog_low + 0.18, uv.y)
		           * (1.0 - smoothstep(fog_high, fog_high + 0.25, uv.y));
		float amt = 0.0;
		for (int k = 0; k < 2; k++) {
			float ph = fract(t * CYCLE + float(k) * 0.5);
			float fade = sin(ph * PI);
			// 两层各自取一片**不同**的噪声（k 那一项给第二层挪开一格），否则同一张噪声配上半拍相位
			// 会在 t 和 t+5 秒处长得一模一样，10 秒的循环缩水成 5 秒、动作看两遍。
			// uv.y 越大越靠画面下边，所以 +ph·rise 是让雾往上飘。
			vec2 np = vec2(uv.x * fog_scale, uv.y * fog_scale + ph * fog_rise)
			        + vec2(37.0, 11.0) * float(k);
			// fbm 输出基本落在 0.2~0.8，这两条线把中间一段拉开，雾才有形状而不是一层平纱。
			amt += smoothstep(fog_thr_low, fog_thr_high, fbm(np)) * fade * fade;
		}
		base = mix(base, fog_color, clamp(amt * band * fog_strength, 0.0, 1.0));
	}

	// 乘 COLOR 就是让底图自己的 modulate（BG_DIM 压暗）继续生效。
	// 漏掉这一步会把压暗冲掉，白字又变回隐形。
	COLOR = vec4(base, tex.a) * COLOR;

	// 天光：日头附近一层暖光随时间明灭。它加在 modulate 之后——光本来就是光源，
	// 比被压暗的画面亮才对；跟着场景一起暗下去反而假。
	if (glow_strength > 0.0) {
		vec2 gd = (UV - glow_center) * vec2(ASPECT, 1.0);
		float g = exp(-length(gd) * 3.0);
		COLOR.rgb += glow_color * g * glow_strength * (0.72 + 0.28 * sin(t * CYCLE * TWO_PI));
	}
}
