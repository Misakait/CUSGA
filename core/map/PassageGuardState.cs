using System.Collections.Generic;
using Godot;

namespace CUSGA.core.map;

/// <summary>
/// 保存当前夜晚已经被怪物驻守的地图通道。
/// </summary>
[GlobalClass]
public partial class PassageGuardState : RefCounted
{
    private readonly HashSet<PassageGuardEdge> _guardedEdges = [];

    /// <summary>
    /// 当前被驻守的通道数量。
    /// </summary>
    public int Count => _guardedEdges.Count;

    /// <summary>
    /// 标记一条通道被驻守。
    /// </summary>
    /// <param name="from">通道的一端。</param>
    /// <param name="to">通道的另一端。</param>
    public void AddGuard(Vector2I from, Vector2I to)
    {
        _guardedEdges.Add(PassageGuardEdge.From(from, to));
    }

    /// <summary>
    /// 查询一条通道当前是否被驻守。
    /// </summary>
    /// <param name="from">通道的一端。</param>
    /// <param name="to">通道的另一端。</param>
    /// <returns>任意方向查询到同一条被驻守通道时返回 true。</returns>
    public bool IsGuarded(Vector2I from, Vector2I to)
    {
        return _guardedEdges.Contains(PassageGuardEdge.From(from, to));
    }

    /// <summary>
    /// 清除一条已经被击败的驻守通道。
    /// </summary>
    /// <param name="from">通道的一端。</param>
    /// <param name="to">通道的另一端。</param>
    public void ClearGuard(Vector2I from, Vector2I to)
    {
        _guardedEdges.Remove(PassageGuardEdge.From(from, to));
    }

    /// <summary>
    /// 清空当前夜晚所有驻守通道。
    /// </summary>
    public void ClearAll()
    {
        _guardedEdges.Clear();
    }
}
