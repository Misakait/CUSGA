using Godot;
using System.Collections.Generic;
using System.Linq;
using CUSGA.core.crafting;
using CUSGA.resources.crafting;

namespace CUSGA.entities.components;

public partial class CraftingComponent : Node
{
    [Signal] public delegate void CraftingCompletedEventHandler(CraftingRecipe recipe, int quantity, int outputAmount);
    [Signal] public delegate void CraftingFailedEventHandler(CraftingRecipe recipe, int quantity, int failureReason);

    [Export] public RecipeBookData RecipeBook { get; set; }

    private readonly CraftingService _craftingService = new();
    private InventoryComponent _inventory = null!;

    public InventoryComponent Inventory => _inventory;
    public IEnumerable<CraftingRecipe> Recipes => RecipeBook?.Recipes?.Where(recipe => recipe != null) ?? [];

    public override void _Ready()
    {
        _inventory = GetParent().GetNode<InventoryComponent>("InventoryComponent");
    }

    public bool CanCraft(CraftingRecipe recipe)
    {
        return CanCraft(recipe, 1);
    }

    public bool CanCraft(CraftingRecipe recipe, int quantity)
    {
        return _craftingService.CanCraft(_inventory, recipe, quantity);
    }

    public int MaxCraftableQuantity(CraftingRecipe recipe)
    {
        return _craftingService.MaxCraftableQuantity(_inventory, recipe);
    }

    public bool TryCraft(CraftingRecipe recipe)
    {
        return TryCraft(recipe, 1, out _);
    }

    public bool TryCraft(CraftingRecipe recipe, int quantity)
    {
        return TryCraft(recipe, quantity, out _);
    }

    public bool TryCraft(CraftingRecipe recipe, int quantity, out CraftingFailureReason failureReason)
    {
        bool crafted = _craftingService.TryCraft(_inventory, recipe, quantity, out failureReason);
        if (crafted)
        {
            int outputAmount = recipe.OutputAmount * quantity;
            EmitSignal(SignalName.CraftingCompleted, recipe, quantity, outputAmount);
            GD.Print($"成功合成了 {outputAmount} 个 {recipe.OutputItem.DisplayName}！");
            return true;
        }

        EmitSignal(SignalName.CraftingFailed, recipe, quantity, (int)failureReason);
        GD.Print(GetFailureMessage(failureReason));
        return false;
    }

    private static string GetFailureMessage(CraftingFailureReason failureReason)
    {
        return failureReason switch
        {
            CraftingFailureReason.MissingMaterials => "材料不足，合成失败！",
            CraftingFailureReason.NotEnoughSpace => "背包空间不足，合成失败！",
            CraftingFailureReason.InvalidQuantity => "合成数量无效，合成失败！",
            _ => "配方无效，合成失败！"
        };
    }
}
