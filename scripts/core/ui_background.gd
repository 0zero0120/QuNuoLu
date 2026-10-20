class_name UIBackground
extends RefCounted

## 整屏界面背景的取图口 + 铺图口。跟 ArtIcons / AudioClips 同一套「资源取用口」形态：
## 数据/场景只给一个 id，能不能取到图由这里判。
##
## **只管网色底那 10 个界面**。战斗场景有自己的背景机制（battle_manager 直接贴
## res://assets/art/backgrounds/ch%d.jpg），**不归这里管**，别去统一它。
##
## 用法：各界面 _ready() 开头一行 `UIBackground.apply(self, "map")`。
##
## **取不到图就什么都不做**——原来那块纯色 Background ColorRect 继续兜底，
## 不会开出透明天窗（与 battle_manager._apply_chapter_background() 同一个口径）。

const DIR := "res://assets/art/ui/"
const EXTS := [".jpg", ".png"]


## 给界面铺背景图。host 下要有名为 Background 的全屏节点（纯色兜底）。
## 在它的**下一个位置**插一个同尺寸 TextureRect，参数照抄战斗场景的 BackgroundImage
## （expand_mode=IGNORE_SIZE / stretch_mode=KEEP_ASPECT_COVERED / mouse_filter=IGNORE）：
## 铺满视口、按比例裁切、不吃鼠标事件（底下的按钮照常点得到）。
##
## dim 小于 1 时把底图整体压暗：底图同一张、界面文字密度不同，靠这个分量
## （0 表示不压暗）。压暗走 modulate，别额外叠一层 Scrim 控件——那层会挡在
## 后面加进来的内容上面，节点次序一不留神就把按钮盖住。
static func apply(host: Node, id: String, dim: float = 1.0) -> void:
	if host == null or not is_instance_valid(host):
		return
	var bg := host.get_node_or_null("Background")
	if bg == null:
		return
	var tex := load_or_null(id)
	if tex == null:
		return
	var img: TextureRect = host.get_node_or_null("BackgroundImage")
	if img == null:
		img = TextureRect.new()
		img.name = "BackgroundImage"
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# **宿主还没 ready 时要排到帧末再加。** 界面 _ready() 里调过来时，宿主可能正处在
		# 「正在铺设子节点」的阻塞态——map_ui.gd 挂在 MapContent 上，宿主是它的**祖先**
		# MapScene 根，而祖先的 _ready 排在子节点之后，此刻它的 blocked 还是 1。
		# 这时候 add_child 会被引擎直接拒掉（"Parent node is busy setting up children"），
		# **只报一条错、图静悄悄地不挂**——背景没了还看不出是代码没跑，最难查的那种。
		# 排到帧末时阻塞已解开；两个 call_deferred 同批按序执行，插在 Background 后面
		# 那一位的次序照旧成立（bg.get_index() 此刻取，批里没有别的节点会挤进来）。
		if host.is_node_ready():
			host.add_child(img)
			host.move_child(img, bg.get_index() + 1)
		else:
			host.add_child.call_deferred(img)
			host.move_child.call_deferred(img, bg.get_index() + 1)
	img.texture = tex
	var shade := clampf(dim, 0.0, 1.0)
	img.modulate = Color(shade, shade, shade, 1.0)


## 取不到就返 null，调用方自己决定退回什么。
## 「exists 过了 load() 还可能返 null」那两道的判断在 ArtIcons.load_or_null 里，这里不重写一份。
## 多出来的只是**扩展名轮询**：整屏底是 .jpg、匾额是 .png，调用方不必知道是哪一种。
static func load_or_null(id: String) -> Texture2D:
	for ext in EXTS:
		var tex := ArtIcons.load_or_null(DIR + id + ext)
		if tex != null:
			return tex
	return null
