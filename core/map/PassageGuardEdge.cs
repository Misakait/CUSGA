using System;
using Godot;

namespace CUSGA.core.map;

/// <summary>
/// 表示两个地图坐标之间的一条无向通道。
/// </summary>
public readonly struct PassageGuardEdge : IEquatable<PassageGuardEdge>
{
    /// <summary>
    /// 创建一个会自动规范化端点顺序的无向通道。
    /// </summary>
    /// <param name="first">通道的任意一端。</param>
    /// <param name="second">通道的另一端。</param>
    public PassageGuardEdge(Vector2I first, Vector2I second)
    {
        if (Compare(first, second) <= 0)
        {
            A = first;
            B = second;
        }
        else
        {
            A = second;
            B = first;
        }
    }

    /// <summary>
    /// 规范化后的第一个端点。
    /// </summary>
    public Vector2I A { get; }

    /// <summary>
    /// 规范化后的第二个端点。
    /// </summary>
    public Vector2I B { get; }

    /// <summary>
    /// 用两个端点创建规范化无向通道。
    /// </summary>
    /// <param name="first">通道的任意一端。</param>
    /// <param name="second">通道的另一端。</param>
    /// <returns>端点顺序稳定的通道值对象。</returns>
    public static PassageGuardEdge From(Vector2I first, Vector2I second)
    {
        return new PassageGuardEdge(first, second);
    }

    /// <inheritdoc />
    public bool Equals(PassageGuardEdge other)
    {
        return A == other.A && B == other.B;
    }

    /// <inheritdoc />
    public override bool Equals(object obj)
    {
        return obj is PassageGuardEdge other && Equals(other);
    }

    /// <inheritdoc />
    public override int GetHashCode()
    {
        return HashCode.Combine(A, B);
    }

    /// <summary>
    /// 判断两个通道是否指向同一条无向边。
    /// </summary>
    /// <param name="left">左侧通道。</param>
    /// <param name="right">右侧通道。</param>
    /// <returns>两个通道规范化后相同则为 true。</returns>
    public static bool operator ==(PassageGuardEdge left, PassageGuardEdge right)
    {
        return left.Equals(right);
    }

    /// <summary>
    /// 判断两个通道是否不是同一条无向边。
    /// </summary>
    /// <param name="left">左侧通道。</param>
    /// <param name="right">右侧通道。</param>
    /// <returns>两个通道规范化后不同则为 true。</returns>
    public static bool operator !=(PassageGuardEdge left, PassageGuardEdge right)
    {
        return !left.Equals(right);
    }

    private static int Compare(Vector2I left, Vector2I right)
    {
        int xCompare = left.X.CompareTo(right.X);
        return xCompare != 0 ? xCompare : left.Y.CompareTo(right.Y);
    }
}
