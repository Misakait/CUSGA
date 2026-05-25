using System;
using System.Collections.Generic;
using CUSGA.resources.map;
using CUSGA.resources.monsters;
using Godot;
using GodotArray = Godot.Collections.Array;
using MonsterArray = Godot.Collections.Array<CUSGA.resources.monsters.MonsterData>;
using PassageEncounterArray = Godot.Collections.Array<CUSGA.resources.map.PassageGuardEncounterData>;

namespace CUSGA.core.map;

/// <summary>
/// 为当前房间中可见的驻守通道解析稳定的怪物组合。
/// </summary>
/// <remarks>
/// 创建使用自定义索引选择器的怪物解析器，主要用于测试稳定性。
/// </remarks>
/// <param name="indexPicker">输入候选数量，返回要使用的索引。</param>
[GlobalClass]
public partial class PassageGuardMonsterResolver(Func<int, int> indexPicker) : RefCounted
{
    private readonly Dictionary<PassageGuardEdge, MonsterArray> _resolvedByEdge = [];
    private readonly Func<int, int> _indexPicker = indexPicker ?? DefaultIndexPicker;

    /// <summary>
    /// 创建使用 Godot 随机源的怪物解析器。
    /// </summary>
    public PassageGuardMonsterResolver()
        : this(DefaultIndexPicker)
    {
    }

    /// <summary>
    /// 开始解析一个新的房间，清除上一房间的按钮缓存。
    /// </summary>
    public void BeginRoom()
    {
        _resolvedByEdge.Clear();
    }

    /// <summary>
    /// 根据当前地图类型的怪物池，为一条驻守通道解析怪物组合。
    /// </summary>
    /// <param name="from">通道的一端。</param>
    /// <param name="to">通道的另一端。</param>
    /// <param name="encounterPool">当前地图类型配置的 encounter 池。</param>
    /// <returns>当前房间内稳定的怪物数组；没有可用配置时返回空数组。</returns>
    public MonsterArray Resolve(
        Vector2I from,
        Vector2I to,
        PassageEncounterArray encounterPool)
    {
        var edge = PassageGuardEdge.From(from, to);
        if (_resolvedByEdge.TryGetValue(edge, out MonsterArray cached))
        {
            return cached;
        }

        MonsterArray resolved = PickEncounter(encounterPool);
        _resolvedByEdge[edge] = resolved;
        return resolved;
    }

    private MonsterArray PickEncounter(PassageEncounterArray encounterPool)
    {
        if (encounterPool == null || encounterPool.Count == 0)
        {
            return [];
        }

        int index = Mathf.Clamp(_indexPicker(encounterPool.Count), 0, encounterPool.Count - 1);
        PassageGuardEncounterData encounter = encounterPool[index];
        if (encounter?.Monsters == null || encounter.Monsters.Count == 0)
        {
            return [];
        }

        var monsters = new MonsterArray();
        foreach (MonsterData monster in encounter.Monsters)
        {
            if (monster != null)
            {
                monsters.Add(monster);
            }
        }

        return monsters;
    }

    private static int DefaultIndexPicker(int count)
    {
        if (count <= 0)
        {
            return 0;
        }

        return (int)(GD.Randi() % (uint)count);
    }
}
