using System;
using System.Collections.Generic;
using CUSGA.core.inventory;
using CUSGA.resources.item;

namespace CUSGA.core.crafting;

public interface ICraftingInventory
{
    IReadOnlyList<ItemStack> Slots { get; }

    bool CanStore(ItemData item);

    int CountWhere(Func<ItemData, bool> predicate);

    int AddItem(ItemData item, int amount);

    bool TryRemoveItems(IReadOnlyDictionary<ItemData, int> itemsToRemove);
}
