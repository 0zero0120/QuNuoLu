class_name VictoryScreen
extends Control

func _ready() -> void:
	UIBackground.apply(self, "victory")
	var result_label: Label = $VBoxContainer.get_node("ResultLabel")
	result_label.text = "你击败了最终首领！\n通关层数: %d    最终金币: %d" % [GameManager.current_floor, GameManager.current_gold]
	$VBoxContainer.get_node("MainMenuButton").pressed.connect(_on_main_menu)

func _on_main_menu() -> void:
	GameManager.change_screen(GameManager.GameScreen.MAIN_MENU)
