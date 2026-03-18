using Godot;
using Godot.Collections;

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

// 定义完整的合成配方图纸
[GlobalClass]
public partial class CraftingRecipe : Resource
{
    [Export] public string RecipeName { get; set; }

    // 需要耗费的所有材料列表
    [Export] public Array<CraftingIngredient> Inputs { get; set; } = [];

    // 输出的物品
    [Export] public ItemData OutputItem { get; set; }

    // 输出数量
    [Export] public int OutputAmount { get; set; } = 1;
}
