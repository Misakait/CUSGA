extends Node

@onready var start_panel = $StartPanel
@onready var settings_panel = $SettingsPanel
@onready var exit_panel = $ExitPanel

func _ready():
	start_panel.connect("start_game", Callable(self, "_on_start_game"))
	settings_panel.connect("open_settings", Callable(self, "_on_open_settings"))
	exit_panel.connect("exit_game", Callable(self, "_on_exit_game"))

func _on_start_game():
	print("开始游戏逻辑，比如切换到游戏场景")

func _on_open_settings():
	print("打开设置界面")

func _on_exit_game():
	print("退出游戏")
