using Godot;
using CUSGA.resources.crafting;

namespace CUSGA.entities.components;

public partial class CraftingComponent : Node
{
    private InventoryComponent _inventory;

    public override void _Ready()
    {
        _inventory = GetParent().GetNode<InventoryComponent>("InventoryComponent");
    }

    public bool CanCraft(CraftingRecipe recipe)
    {
        if (recipe == null || recipe.Inputs.Count == 0) return false;

        foreach (var ingredient in recipe.Inputs)
        {
            if (!_inventory.HasItem(ingredient.RequiredItem, ingredient.Amount))
            {
                return false;
            }
        }
        return true;
    }


    public bool TryCraft(CraftingRecipe recipe)
    {
        if (!CanCraft(recipe))
        {
            GD.Print("材料不足，合成失败！");
            return false;
        }

        // 扣除所有输入材料
        foreach (var ingredient in recipe.Inputs)
        {
            _inventory.RemoveItem(ingredient.RequiredItem, ingredient.Amount);
        }

        // 发放输出物品
        _inventory.AddItem(recipe.OutputItem, recipe.OutputAmount);

        GD.Print($"成功合成了 {recipe.OutputAmount} 个 {recipe.OutputItem.CardName}！");
        return true;
    }
}
