extends Node2D


func _on_card_be_snapper(node_name: Variant) -> void:
	match node_name:
		"StartCard":
			print("Start!")
		"SettingsCard":
			print("Setting!")
		"ExitCard":
			print("Exit?How dare you!!")
		"Warehouse":
			print("Warehouse!!")
		"_":
			print("出现了不该出现的卡牌，去SnapPoint看看吧！")
