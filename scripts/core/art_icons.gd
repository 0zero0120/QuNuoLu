class_name ArtIcons
extends RefCounted

## 遗物 / 成就 / 药水这三块图标的取图口。跟 CardData.get_art_path() 同一套口径：
## 数据类只给路径，能不能取到图由这里判。**缺图不是错误状态**——取不到就返 null，
## 各显示点各自退回原样（遗物退回 🔹、药水退回程序像素画、百科退回首字/挂锁）。


## 取不到就返 null，调用方自己决定退回什么。
##
## **两道判断都得有**：ResourceLoader.exists() 返 true 而 load() 返 null 是真会发生的
## ——`.import` 在仓库里而 `.godot/imported/` 里的 `.ctex` 还没导出来时就是这样。
## 只判前者会拿到一个空白纹理，比 null 更难查。card.gd 的 _update_art() 撞过这个坑。
##
## **刻意不缓存**：跟 card.gd 保持一致；缓存 null 会在「刚落完图还没重启」时骗人。
static func load_or_null(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
