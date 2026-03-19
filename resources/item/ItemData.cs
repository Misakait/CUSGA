using Godot;
using Godot.Collections;

namespace CUSGA.resources.item;

[GlobalClass]
public partial class ItemData : Resource
{
	[Export] public string ItemName { get; set; } = "未知物品";
	[Export] public Texture2D Icon { get; set; }

	[Export] public int MaxStackSize { get; set; } = 99;

	// 物品标签
	[Export] public Array<StringName> ItemTags { get; set; } = [];
}
