using System;
using System.Collections.Generic;
using System.Linq;
using CUSGA.resources.crafting;
using CUSGA.resources.item;
using Godot;

namespace CUSGA.core.crafting;

public sealed class CraftingService
{
    public bool CanCraft(ICraftingInventory inventory, CraftingRecipe recipe, int quantity = 1)
    {
        if (!TryBuildRequirements(recipe, quantity, out var requirements))
        {
            return false;
        }

        return HasRequiredMaterials(inventory, requirements)
            && CanReceiveOutputAfterConsuming(inventory, recipe, quantity, requirements);
    }

    public int MaxCraftableQuantity(ICraftingInventory inventory, CraftingRecipe recipe)
    {
        // 计算单次合成需要什么
        if (inventory == null || !TryBuildRequirements(recipe, 1, out var singleCraftRequirements))
        {
            return 0;
        }

        // 根据材料数量算理论最大合成次数
        int maxByMaterials = int.MaxValue;
        foreach (var requirement in singleCraftRequirements)
        {
            // 当前背包中拥有这种材料的总数量
            int owned = inventory.CountWhere(item => item == requirement.Key);
            // 取所有材料中，最短板的那个数量
            maxByMaterials = Math.Min(maxByMaterials, owned / requirement.Value);
        }

        // 如果材料都不够，直接返回 0
        if (maxByMaterials == int.MaxValue || maxByMaterials <= 0)
        {
            return 0;
        }

        // 用二分查找找真正最大值
        // 在材料够的前提下，背包空间够不够放产物
        int low = 0;
        int high = maxByMaterials;
        while (low < high)
        {
            // 向上取中点，避免 low = mid 时死循环
            int mid = low + ((high - low + 1) / 2);
            if (CanCraft(inventory, recipe, mid))
            {
                low = mid;
            }
            else
            {
                high = mid - 1;
            }
        }

        return low;
    }

    public bool TryCraft(ICraftingInventory inventory, CraftingRecipe recipe, int quantity, out CraftingFailureReason failureReason)
    {
        failureReason = CraftingFailureReason.None;

        if (inventory == null || !IsRecipeValid(recipe))
        {
            failureReason = CraftingFailureReason.InvalidRecipe;
            return false;
        }

        if (quantity <= 0)
        {
            failureReason = CraftingFailureReason.InvalidQuantity;
            return false;
        }

        if (!TryBuildRequirements(recipe, quantity, out var requirements))
        {
            failureReason = CraftingFailureReason.InvalidQuantity;
            return false;
        }

        if (!HasRequiredMaterials(inventory, requirements))
        {
            failureReason = CraftingFailureReason.MissingMaterials;
            return false;
        }

        if (!CanReceiveOutputAfterConsuming(inventory, recipe, quantity, requirements))
        {
            failureReason = CraftingFailureReason.NotEnoughSpace;
            return false;
        }

        if (!inventory.TryRemoveItems(requirements))
        {
            failureReason = CraftingFailureReason.MissingMaterials;
            return false;
        }

        int outputAmount = recipe.OutputAmount * quantity;
        int remaining = inventory.AddItem(recipe.OutputItem, outputAmount);
        if (remaining > 0)
        {
            failureReason = CraftingFailureReason.NotEnoughSpace;
            return false;
        }

        return true;
    }

    public bool TryBuildRequirements(CraftingRecipe recipe, int quantity, out Dictionary<ItemData, int> requirements)
    {
        requirements = [];
        if (!IsRecipeValid(recipe) || quantity <= 0)
        {
            return false;
        }

        foreach (var ingredient in recipe.Inputs)
        {
            long requiredAmount = (long)ingredient.Amount * quantity;
            if (requiredAmount > int.MaxValue)
            {
                return false;
            }

            if (requirements.TryGetValue(ingredient.RequiredItem, out int currentAmount))
            {
                requiredAmount += currentAmount;
                if (requiredAmount > int.MaxValue)
                {
                    return false;
                }
            }

            requirements[ingredient.RequiredItem] = (int)requiredAmount;
        }

        return requirements.Count > 0;
    }

    public bool HasRequiredMaterials(ICraftingInventory inventory, IReadOnlyDictionary<ItemData, int> requirements)
    {
        if (inventory == null || requirements == null || requirements.Count == 0)
        {
            GD.Print("inventory: " + inventory + " requirements: " + requirements + " requirements.Count: " + requirements.Count);
            return false;
        }

        foreach (var requirement in requirements)
        {
            if (requirement.Key == null || requirement.Value <= 0)
            {
                return false;
            }

            if (inventory.CountWhere(item => item == requirement.Key) < requirement.Value)
            {
                return false;
            }
        }

        return true;
    }

    public bool CanReceiveOutputAfterConsuming(
        ICraftingInventory inventory,
        CraftingRecipe recipe,
        int quantity,
        IReadOnlyDictionary<ItemData, int> requirements
    )
    {
        if (inventory == null || !IsRecipeValid(recipe) || requirements == null || !inventory.CanStore(recipe.OutputItem))
        {
            return false;
        }

        long outputAmount = (long)recipe.OutputAmount * quantity;
        if (outputAmount <= 0 || outputAmount > int.MaxValue || recipe.OutputItem.ActualMaxStackSize <= 0)
        {
            return false;
        }

        // 复制出一份虚拟背包
        var virtualSlots = inventory.Slots
            .Select(stack => new VirtualStack(stack?.Item, stack?.Amount ?? 0))
            .ToList();

        // 模拟扣除材料
        foreach (var requirement in requirements)
        {
            int remainingToRemove = requirement.Value;
            // 从背包后面往前找这种材料
            for (int i = virtualSlots.Count - 1; i >= 0 && remainingToRemove > 0; i--)
            {
                var slot = virtualSlots[i];
                if (slot.Item != requirement.Key)
                {
                    continue;
                }

                int removed = Math.Min(slot.Amount, remainingToRemove);
                slot.Amount -= removed;
                remainingToRemove -= removed;
                if (slot.Amount <= 0)
                {
                    slot.Clear();
                }
            }
            // 如果整个背包扣完还不够，说明材料不足，返回 false
            if (remainingToRemove > 0)
            {
                return false;
            }
        }

        // 模拟把产物放进背包
        int remainingOutput = (int)outputAmount;
        // 优先塞进已有的同类堆叠
        foreach (var slot in virtualSlots)
        {
            if (slot.Item == recipe.OutputItem && slot.Amount < recipe.OutputItem.ActualMaxStackSize)
            {
                int amountToAdd = Math.Min(remainingOutput, recipe.OutputItem.ActualMaxStackSize - slot.Amount);
                slot.Amount += amountToAdd;
                remainingOutput -= amountToAdd;
                if (remainingOutput <= 0)
                {
                    return true;
                }
            }
        }

        // 如果同类堆叠塞不下，就找空格子
        foreach (var slot in virtualSlots)
        {
            if (slot.Item != null)
            {
                continue;
            }

            int amountToAdd = Math.Min(remainingOutput, recipe.OutputItem.ActualMaxStackSize);
            slot.Item = recipe.OutputItem;
            slot.Amount = amountToAdd;
            remainingOutput -= amountToAdd;
            if (remainingOutput <= 0)
            {
                return true;
            }
        }

        // 扣完材料之后，背包仍然没有足够空间容纳产物。
        return false;
    }

    private static bool IsRecipeValid(CraftingRecipe recipe)
    {
        if (recipe == null || recipe.OutputItem == null || recipe.OutputAmount <= 0 || recipe.Inputs == null || recipe.Inputs.Count == 0)
        {
            return false;
        }

        foreach (var ingredient in recipe.Inputs)
        {
            if (ingredient == null || ingredient.RequiredItem == null || ingredient.Amount <= 0)
            {
                return false;
            }
        }

        return true;
    }

    private sealed class VirtualStack
    {
        public VirtualStack(ItemData item, int amount)
        {
            Item = item != null && amount > 0 ? item : null;
            Amount = Item != null ? amount : 0;
        }

        public ItemData Item { get; set; }
        public int Amount { get; set; }

        public void Clear()
        {
            Item = null;
            Amount = 0;
        }
    }
}
