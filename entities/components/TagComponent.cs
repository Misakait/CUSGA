using Godot;
using System.Collections.Generic;

namespace CUSGA.entities.components;

public partial class TagComponent : Node
{
    private readonly Dictionary<StringName, int> _activeTags = [];

    // 增加标签（天赋获得、穿上装备时调用）
    public void AddTag(StringName tag)
    {
        if (tag == null || tag.IsEmpty) return;

        // 尝试放入初始值 0 (如果已存在则会被自动忽略)
        _activeTags.TryAdd(tag, 0);

        _activeTags[tag]++; // 层数 +1

        GD.Print($"[标签系统] 获得标签 {tag}，当前层数：{_activeTags[tag]}");
    }

    // 移除标签（脱下装备、Buff到期时调用）
    public void RemoveTag(StringName tag)
    {
        if (tag == null || tag.IsEmpty) return;

        if (_activeTags.ContainsKey(tag))
        {
            _activeTags[tag]--; // 层数 -1

            GD.Print($"[标签系统] 移除标签 {tag}，当前层数：{_activeTags[tag]}");

            // 当层数归零时，从字典里清除
            if (_activeTags[tag] <= 0)
            {
                _activeTags.Remove(tag);
                GD.Print($"[标签系统] 标签 {tag} 已彻底失效！");
            }
        }
    }

    public bool HasTag(StringName tag)
    {
        return _activeTags.ContainsKey(tag);
    }

    // 获取标签的层数
    public int GetTagStack(StringName tag)
    {
        return _activeTags.TryGetValue(tag, out int value) ? value : 0;
    }
}
