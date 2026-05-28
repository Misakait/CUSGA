using Godot;

namespace CUSGA.entities.components;

/// <summary>
/// 提供实体组件节点的兼容查找方法，隔离不同场景结构造成的节点路径差异。
/// </summary>
public static class ComponentLookup
{
    /// <summary>
    /// 从指定宿主节点查找状态组件，兼容直接子节点、Components 子节点和唯一名称节点三种场景结构。
    /// </summary>
    /// <param name="owner">拥有状态组件的实体节点。</param>
    /// <returns>找到的状态组件；如果宿主为空或不存在状态组件，则返回 null。</returns>
    public static StatusComponent GetStatusComponentOrNull(this Node owner)
    {
        if (owner == null)
        {
            return null;
        }

        // 兼容旧场景的直接子节点结构，以及当前实体常用的 Components 容器结构。
        return owner.GetNodeOrNull<StatusComponent>("StatusComponent")
            ?? owner.GetNodeOrNull<StatusComponent>("Components/StatusComponent")
            ?? owner.GetNodeOrNull<StatusComponent>("%StatusComponent");
    }
}
