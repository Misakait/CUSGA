using System;

namespace CUSGA.core.attributes;

public enum AttributeType
{
    PhysAtk,  // 物攻
    PhysDef,  // 物抗
    MagPower, // 法强
    MagResist,// 法抗
    Speed     // 速度
}

public class Attribute(AttributeType type, string displayName, float baseValue, float growthPerPoint)
{
    public AttributeType Type { get; private set; } = type;
    public string DisplayName { get; private set; } = displayName;

    // 基础值
    public float BaseValue { get; private set; } = baseValue;

    // 来自天赋、装备、永久药水等提供的额外固定加成
    public float BonusValue { get; private set; }

    // 玩家投入的属性点数
    public int AllocatedPoints { get; private set; } = 0;

    // 每投入1点，属性增长多少
    public float GrowthPerPoint { get; private set; } = growthPerPoint;

    // 动态计算的最终值
    public float Value => BaseValue + (AllocatedPoints * GrowthPerPoint) + BonusValue;

    public event Action<Attribute> OnAttributeChanged;

    public void AddPoint(int amount)
    {
        AllocatedPoints += amount;
        OnAttributeChanged?.Invoke(this);
    }

    public void AddBonus(float amount)
    {
        BonusValue += amount;
        OnAttributeChanged?.Invoke(this);
    }
    public void RemoveBonus(float amount)
    {
        BonusValue -= amount;
        OnAttributeChanged?.Invoke(this);
    }
}
