using Godot;
using CUSGA.resources.item;

namespace CUSGA.resources.crafting;

// 定义单种材料的需求
[GlobalClass]
public partial class CraftingIngredient : Resource
{
    // 需要的物品
    [Export] public ItemData RequiredItem { get; set; }

    // 需要的个数
    [Export] public int Amount { get; set; } = 1;
}
