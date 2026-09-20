using Godot;

namespace CUSGA.core.inventory;

/// <summary>
/// 集中读取旧 C# 与 GDScript ItemStack 共同保留的稳定属性协议。
/// </summary>
internal static class ItemStackProtocol
{
    private static readonly StringName SetItemMethod = "SetItem";
    private static readonly StringName ClearMethod = "Clear";
    private static readonly StringName ItemProperty = "Item";
    private static readonly StringName AmountProperty = "Amount";
    private static readonly StringName IsEmptyProperty = "IsEmpty";

    /// <summary>
    /// 尝试从跨语言物品堆叠读取有效物品资源和正数量。
    /// </summary>
    /// <param name="stack">待检查的旧 C# 或 GDScript RefCounted。</param>
    /// <param name="item">成功时返回堆叠持有的原始物品资源。</param>
    /// <param name="amount">成功时返回堆叠数量。</param>
    /// <returns>对象声明完整协议、非空且数量为正时返回 <see langword="true"/>。</returns>
    public static bool TryRead(RefCounted stack, out Resource item, out int amount)
    {
        item = null;
        amount = 0;
        if (stack == null
            || !GodotObject.IsInstanceValid(stack)
            || !stack.HasMethod(SetItemMethod)
            || !stack.HasMethod(ClearMethod))
        {
            return false;
        }

        item = stack.Get(ItemProperty).AsGodotObject() as Resource;
        amount = stack.Get(AmountProperty).AsInt32();
        bool isEmpty = stack.Get(IsEmptyProperty).AsBool();
        return !isEmpty && item != null && amount > 0;
    }
}
