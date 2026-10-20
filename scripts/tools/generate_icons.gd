extends Node
## Run this scene (F6) to generate all pixel art icons in assets/icons/

const OUT_DIR := "res://assets/icons"
const SIZE := 16

# ── Color encoding ──────────────────────────────────────────
# Each character in a design row maps to a color via its palette

func _palette_sword(ch: String) -> Color:
	match ch:
		"@": return Color("7b1f18")
		"#": return Color("a92c20")
		"=": return Color("cb3a2e")
		"-": return Color("e85d53")
		"+": return Color("f5aaa2")
		"o": return Color("ffdc78")
		"x": return Color("c48b3a")
	return Color(0,0,0,0)

func _palette_diamond(ch: String) -> Color:
	match ch:
		"@": return Color("153e5c")
		"#": return Color("1f5c8a")
		"=": return Color("2c80ba")
		"-": return Color("5baedb")
		"+": return Color("a8d8f0")
	return Color(0,0,0,0)

func _palette_star(ch: String) -> Color:
	match ch:
		"@": return Color("114d2a")
		"#": return Color("1a703e")
		"=": return Color("27ae60")
		"-": return Color("5ccc8a")
		"+": return Color("a0e8c0")
	return Color(0,0,0,0)

func _palette_health(ch: String) -> Color:
	match ch:
		"@": return Color("7b1f18")
		"#": return Color("c0392b")
		"=": return Color("e74c3c")
		"-": return Color("f1948a")
		"+": return Color("fdd8d4")
		"w": return Color("fdf2f0")
	return Color(0,0,0,0)

func _palette_strength(ch: String) -> Color:
	match ch:
		"@": return Color("933a0a")
		"#": return Color("c0530e")
		"=": return Color("e67e22")
		"-": return Color("f0a86a")
		"+": return Color("f8cda8")
	return Color(0,0,0,0)

func _palette_block(ch: String) -> Color:
	match ch:
		"@": return Color("3d4f5f")
		"#": return Color("566d7e")
		"=": return Color("7f96a8")
		"-": return Color("a8bcc8")
		"+": return Color("d0dde4")
	return Color(0,0,0,0)

func _palette_energy(ch: String) -> Color:
	match ch:
		"@": return Color("8c6d08")
		"#": return Color("b7950b")
		"=": return Color("e6be0e")
		"-": return Color("f5d547")
		"+": return Color("fbea9e")
	return Color(0,0,0,0)

func _palette_explosive(ch: String) -> Color:
	match ch:
		"@": return Color("7b1f18")
		"#": return Color("c0392b")
		"=": return Color("e74c3c")
		"-": return Color("f39c12")
		"+": return Color("fbca5e")
	return Color(0,0,0,0)

# ── 16x16 pixel designs (row strings, '.' = transparent) ────

const SWORD := [
	"......++........",
	".....+--+.......",
	".....=@@=.......",
	".....=--=.......",
	".....=@@=.......",
	".....=--=.......",
	"....o=@@=o......",
	"...o==--==o.....",
	"..o========o....",
	"....=--=........",
	"....=--=........",
	"....=--=........",
	"....x@@x........",
	"....x--x........",
	"....x@@x........",
	"....x--x........",
]

const DIAMOND := [
	"................",
	"......@@.......",
	".....@--@......",
	"....@=--=@.....",
	"...@=====@.....",
	"..@=======@....",
	".@=========@...",
	".@=++===++=@...",
	".@=++===++=@...",
	".@=========@...",
	"..@=======@....",
	"...@=====@.....",
	"....@===@......",
	".....@-@.......",
	"......@@.......",
	"................",
]

const STAR := [
	"................",
	"......@@.......",
	".....@--@......",
	"....@=--=@.....",
	"...@=====@.....",
	"..@=@@-@@=@....",
	".@==@---@==@...",
	".@=========@...",
	"@=@@-----@@=@..",
	".@==@---@==@...",
	".@==@-@-@==@...",
	"..@=@@@@@=@....",
	"...@=====@.....",
	"....@===@......",
	".....@-@.......",
	"......@........",
]

const HEALTH := [
	"................",
	"......@@@......",
	".....@@@@@.....",
	"....@@www@@....",
	"....@www@@@....",
	"...@@ww@@=@....",
	"...@@w@@==@....",
	"..@@=@@===@....",
	"..@@@=====@....",
	".@@=@=====@....",
	".@==@=====@....",
	"...@======@....",
	"...@=====@.....",
	"...@====@......",
	"....@==@.......",
	".....@@........",
]

const STRENGTH := [
	"................",
	"......@@@......",
	".....@+++@.....",
	"....@++#++@....",
	"....@+#=#+@....",
	"....@+#=#+@....",
	"....++#=#++....",
	".....+###+.....",
	"......@@@......",
	".....@+++@.....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	".....@@@@......",
	"......@@.......",
]

const BLOCK := [
	"................",
	"......@@@......",
	".....@+++@.....",
	"....@+@@@+@....",
	"....@+@#@+@....",
	"....@+@#@+@....",
	"....@+@#@+@....",
	".....@@@@@.....",
	"......@@@......",
	".....@+++@.....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	".....@@@@......",
	"......@@.......",
]

const ENERGY := [
	"................",
	"......@@@......",
	".....@+++@.....",
	"....@++#++@....",
	"....@++#=#@....",
	".....+###+.....",
	"......#=#......",
	".....+###+......",
	"......@@@......",
	".....@+++@.....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	".....@@@@......",
	"......@@.......",
]

const EXPLOSIVE := [
	"................",
	"......@@@......",
	".....@+++@.....",
	"....@+###+@....",
	"....@#####@....",
	".....@#@#@.....",
	"....@#####@....",
	"....@#@@@#@....",
	"......@@@......",
	".....@+++@.....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	"....@+++++@....",
	".....@@@@......",
	"......@@.......",
]

func _ready() -> void:
	print("Generating pixel art icons...")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_generate("icon_attack", SWORD, _palette_sword)
	_generate("icon_skill", DIAMOND, _palette_diamond)
	_generate("icon_ability", STAR, _palette_star)
	_generate("icon_health_potion", HEALTH, _palette_health)
	_generate("icon_strength_potion", STRENGTH, _palette_strength)
	_generate("icon_block_potion", BLOCK, _palette_block)
	_generate("icon_energy_potion", ENERGY, _palette_energy)
	_generate("icon_explosive_potion", EXPLOSIVE, _palette_explosive)

	print("✅ Done! 8 icons saved to ", OUT_DIR)
	print("You can now close this scene.")

	# Auto-quit after generation
	var tree := get_tree()
	if tree:
		tree.quit(0)


func _generate(filename: String, design: Array, palette_func: Callable) -> void:
	var img_16 := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in range(SIZE):
		var row: String = design[y]
		for x in range(SIZE):
			var ch := "." if x >= row.length() else row[x]
			var col: Color = palette_func.call(ch)
			img_16.set_pixel(x, y, col)

	# Nearest-neighbor 2x scale to 32x32
	var img_32: Image = img_16.duplicate()
	img_32.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_NEAREST)

	var path := OUT_DIR + "/" + filename + ".png"
	var err: Error = img_32.save_png(path)
	if err == OK:
		print("  OK ", path)
	else:
		push_error("  FAILED: %s (err=%d)" % [path, err])
