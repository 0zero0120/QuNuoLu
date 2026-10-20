class_name GameOverScreen
extends Control

func _ready() -> void:
	UIBackground.apply(self, "game_over")
	var vbox := $VBoxContainer
	vbox.get_node("MainMenuButton").pressed.connect(_on_main_menu)

func _on_main_menu() -> void:
	GameManager.change_screen(GameManager.GameScreen.MAIN_MENU)
