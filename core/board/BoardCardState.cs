using System;
using CUSGA.core.inventory;
using CUSGA.resources.interaction;
using CUSGA.resources.item;

namespace CUSGA.core.board;

public abstract class BoardCardState
{
    public abstract BaseCardData CardData { get; }

    public virtual int? StackAmount => null;
    public virtual bool CanShowAmount => false;
}

public sealed class LootBoardCardState : BoardCardState
{
    public ItemStack LootStack { get; }

    public ItemData ItemData => LootStack.Item;

    public override BaseCardData CardData => LootStack.Item;
    public override int? StackAmount => LootStack.Amount;
    public override bool CanShowAmount => LootStack.Amount > 1;

    public LootBoardCardState(ItemStack lootStack)
    {
        LootStack = lootStack ?? throw new ArgumentNullException(nameof(lootStack));
        if (lootStack.Item == null)
        {
            throw new ArgumentException("LootStack.Item 不能为空。", nameof(lootStack));
        }
    }
}

public sealed class TerrainBoardCardState : BoardCardState
{
    public TerrainInstance TerrainInstance { get; }

    public TerrainCardData TerrainData => TerrainInstance.TerrainData;

    public override BaseCardData CardData => TerrainInstance.TerrainData;

    public TerrainBoardCardState(TerrainInstance terrainInstance)
    {
        TerrainInstance = terrainInstance ?? throw new ArgumentNullException(nameof(terrainInstance));
        if (terrainInstance.TerrainData == null)
        {
            throw new ArgumentException("TerrainInstance.TerrainData 不能为空。", nameof(terrainInstance));
        }
    }
}
