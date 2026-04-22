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
// public sealed class BoardCardState
// {
//     public BoardCardKind Kind { get; }

//     public ItemStack LootStack { get; }

//     public TerrainCardData TerrainData { get; }

//     public BaseCardData CardData =>
//         Kind switch
//         {
//             BoardCardKind.Loot => LootStack?.Item,
//             BoardCardKind.Terrain => TerrainData,
//             _ => null
//         };


//     public ItemData ItemData => LootStack?.Item;

//     public bool IsLoot => Kind == BoardCardKind.Loot;
//     public bool IsTerrain => Kind == BoardCardKind.Terrain;
//     public int DisplayAmount => LootStack?.Amount ?? 0;

//     private BoardCardState(BoardCardKind kind, ItemStack lootStack = null, TerrainCardData terrainData = null)
//     {
//         Kind = kind;
//         LootStack = lootStack;
//         TerrainData = terrainData;
//     }

//     public static BoardCardState CreateLoot(ItemStack stack)
//     {
//         ArgumentNullException.ThrowIfNull(stack);
//         if (stack.Item == null) throw new ArgumentException("LootStack.Item 不能为空", nameof(stack));

//         return new BoardCardState(BoardCardKind.Loot, lootStack: stack);
//     }

//     public static BoardCardState CreateTerrain(TerrainCardData terrainData)
//     {
//         ArgumentNullException.ThrowIfNull(terrainData);

//         return new BoardCardState(BoardCardKind.Terrain, terrainData: terrainData);
//     }
// }
