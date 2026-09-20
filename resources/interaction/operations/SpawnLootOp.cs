using Godot;
using Godot.Collections;
using CUSGA.core.inventory;

namespace CUSGA.resources.interaction.operations;

/// <summary>
/// 把旧 C# 或 GDScript ItemStack 数组转交给棋盘端口生成掉落卡。
/// </summary>
public sealed partial class SpawnLootOp : TerrainOp
{
    /// <summary>
    /// 获取跨语言物品堆叠数组；元素在棋盘边界统一按 RefCounted 协议读取。
    /// </summary>
    public Array Drops { get; }

    /// <summary>
    /// 创建接收 GDScript 非泛型数组的掉落操作。
    /// </summary>
    /// <param name="drops">由兼容 ItemStack 组成的非泛型数组。</param>
    public SpawnLootOp(Array drops)
    {
        Drops = drops ?? [];
    }

    /// <summary>
    /// 创建接收旧 C# 强类型数组的掉落操作。
    /// </summary>
    /// <param name="drops">旧 C# 交互资源生成的 ItemStack 数组。</param>
    public SpawnLootOp(Array<ItemStack> drops)
    {
        Drops = [];
        if (drops == null)
        {
            return;
        }

        // 显式复制到非泛型数组，避免依赖 Godot 泛型数组的跨语言隐式封送。
        foreach (ItemStack stack in drops)
        {
            if (stack != null)
            {
                Drops.Add(Variant.From(stack));
            }
        }
    }

    /// <summary>
    /// 将非空掉落数组交给棋盘端口执行。
    /// </summary>
    /// <param name="context">包含棋盘端口与生成位置的局外交互上下文。</param>
    public override void Apply(WorldInteractionContext context)
    {
        if (Drops.Count == 0)
        {
            return;
        }

        context.Board.SpawnLootCards(Drops, context.SourceGlobalPosition);
    }
}
