using Godot;
using System;
using System.Collections.Generic;
using CUSGA.core.attributes;
using CUSGA.core;
using CUSGA.resources.stats;
namespace CUSGA.entities.components;

public partial class AttributeComponent : Node
{
    [Export] public StartingStats InitialData;
    // 当前拥有的可用技能点
    public int AvailablePoints { get; private set; } = 0;

    private readonly Dictionary<AttributeType, core.attributes.Attribute> _attributes = [];

    // 当可用点数变化时通知 UI
    public event Action<int> OnAvailablePointsChanged;

    public override void _Ready()
    {
        // 在这里初始化主角的初始面板（这里的数据未来可以通过 Resource 配置文件传入以实现彻底解耦）
        _attributes.Add(AttributeType.PhysAtk, new core.attributes.Attribute(AttributeType.PhysAtk, "物理攻击", InitialData.BasePhysAtk, InitialData.PhysAtkGrowth));
        _attributes.Add(AttributeType.PhysDef, new core.attributes.Attribute(AttributeType.PhysDef, "物理抗性", InitialData.BasePhysDef, InitialData.PhysDefGrowth));
        _attributes.Add(AttributeType.MagPower, new core.attributes.Attribute(AttributeType.MagPower, "法术强度", InitialData.BaseMagPower, InitialData.MagPowerGrowth));
        _attributes.Add(AttributeType.MagResist, new core.attributes.Attribute(AttributeType.MagResist, "法术抗性", InitialData.BaseMagResist, InitialData.MagResistGrowth));
        _attributes.Add(AttributeType.Speed, new core.attributes.Attribute(AttributeType.Speed, "速度", InitialData.BaseSpeed, InitialData.SpeedGrowth));
    }

    public core.attributes.Attribute GetAttribute(AttributeType type)
    {
        return _attributes.TryGetValue(type, out var attribute) ? attribute : null;
    }

    public IEnumerable<core.attributes.Attribute> GetAllAttributes()
    {
        return _attributes.Values;
    }

    public void EarnPoints(int amount)
    {
        AvailablePoints += amount;
        OnAvailablePointsChanged?.Invoke(AvailablePoints);
    }

    // UI 尝试加点时调用
    public bool TryAllocatePoint(AttributeType targetAttributeType, int amount)
    {
        if (AvailablePoints < amount)
        {
            GD.Print("没有足够的技能点！");
            return false;
        }

        if (_attributes.TryGetValue(targetAttributeType, out core.attributes.Attribute attribute))
        {
            AvailablePoints--;
            attribute.AddPoint(amount);

            OnAvailablePointsChanged?.Invoke(AvailablePoints);
            return true;
        }

        return false;
    }
}
