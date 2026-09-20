extends Resource

## 一项可供玩家选择的天赋数据。

## 天赋显示名称。
@export var TalentName: String = ""

## 天赋的多行说明文本。
@export_multiline var Description: String = ""

## 天赋卡显示图片。
@export var TalentTexture: Texture2D

## 选择后依次应用的旧 C# 或新 GDScript TalentEffect Resource。
@export var Effects: Array[Resource] = []
