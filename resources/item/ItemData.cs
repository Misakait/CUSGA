using Godot;
using Godot.Collections;

namespace CUSGA.resources.item;

[GlobalClass]
public partial class ItemData : BaseCardData
{
	[Export] public int MaxStackSize { get; set; } = 99;

	// 物品标签
	[Export] public Array<StringName> ItemTags { get; set; } = [];
}
