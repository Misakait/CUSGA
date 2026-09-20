using System;
using Godot;
using CUSGA.core.inventory;
using CUSGA.resources.interaction;

namespace CUSGA.core.board;

public abstract class BoardCardState
{
    public abstract global::Godot.Resource CardData { get; }

    public virtual int? StackAmount => null;
    public virtual bool CanShowAmount => false;
}

public sealed class LootBoardCardState : BoardCardState
{
    /// <summary>
    /// 获取当前掉落卡持有的物品堆叠；允许旧 C# 与 GDScript ItemStack 共存。
    /// </summary>
    public RefCounted LootStack { get; }

    /// <summary>
    /// 获取堆叠中的原始物品资源，保留跨语言对象身份。
    /// </summary>
    public Resource ItemData => ItemStackProtocol.TryRead(LootStack, out Resource item, out _)
        ? item
        : null;

    public override global::Godot.Resource CardData => ItemData;
    public override int? StackAmount => ItemStackProtocol.TryRead(LootStack, out _, out int amount)
        ? amount
        : null;
    public override bool CanShowAmount => StackAmount > 1;

    /// <summary>
    /// 创建一个保留原物品堆叠引用的掉落卡状态。
    /// </summary>
    /// <param name="lootStack">实现 Item、Amount 与 IsEmpty 稳定属性协议的物品堆叠。</param>
    /// <exception cref="ArgumentNullException">堆叠为空时抛出。</exception>
    /// <exception cref="ArgumentException">堆叠没有有效物品资源时抛出。</exception>
    public LootBoardCardState(RefCounted lootStack)
    {
        LootStack = lootStack ?? throw new ArgumentNullException(nameof(lootStack));
        if (!ItemStackProtocol.TryRead(lootStack, out _, out _))
        {
            throw new ArgumentException(
                "LootStack 必须提供非空 Item、正 Amount 与 IsEmpty 属性。",
                nameof(lootStack)
            );
        }
    }
}

public sealed class TerrainBoardCardState : BoardCardState
{
    public TerrainInstance TerrainInstance { get; }

    public global::Godot.Resource TerrainData => TerrainInstance.TerrainData;

    public override global::Godot.Resource CardData => TerrainInstance.TerrainData;

    public TerrainBoardCardState(TerrainInstance terrainInstance)
    {
        TerrainInstance = terrainInstance ?? throw new ArgumentNullException(nameof(terrainInstance));
        if (terrainInstance.TerrainData == null)
        {
            throw new ArgumentException("TerrainInstance.TerrainData 不能为空。", nameof(terrainInstance));
        }
    }
}
