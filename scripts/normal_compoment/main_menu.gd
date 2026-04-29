extends Node2D

#这里是接口
func _on_card_be_snapper(node_name: Variant) -> void:
	match node_name:
		"StartCard":
			#在这里填上你想要的方法
			print("Start!")
		"SettingsCard":
			print("Setting!")
		"ExitCard":
			print("Exit?How dare you!!")
		"Warehouse":
			print("Warehouse!!")
		"_":
			print("出现了不该出现的卡牌，去SnapPoint看看吧！")
