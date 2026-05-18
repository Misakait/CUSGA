extends Node

const Main_scene_path = "res://scenes/Main.tscn"

#这里是接口
func _on_card_be_snapper(node_name: Variant) -> void:
	match node_name:
		"StartCard":

			get_tree().change_scene_to_file(Main_scene_path)

			print("Start!")
		"SettingsCard":
			print("Setting!")
		"ExitCard":
			print("Exit?How dare you!!")
		"Warehouse":
			GlobalEventBus.scene_requested.emit("warehouse")
			print("Warehouse!!")
		"_":
			print("出现了不该出现的卡牌，去SnapPoint看看吧！")
