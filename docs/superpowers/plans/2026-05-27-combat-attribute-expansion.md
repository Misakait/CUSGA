# Combat Attribute Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand CUSGA combat attributes and damage resolution with crit, evasion, lifesteal, fixed/rate penetration, random variance, and attribute-owned health/energy maxima.

**Architecture:** Keep stat ownership in `AttributeComponent`, pure arithmetic in `DamageFormula`, and Godot node lookup/RNG in `DamageReceiverComponent`. `StartingStats` becomes the base data source for max health and max energy; vitals expose actual value changes so lifesteal can use final actual damage.

**Tech Stack:** Godot 4.6 Mono, C# net8.0, existing console test harness in `tests/CUSGA.Tests/Program.cs`, `.tscn` scene resources.

---

## File Structure

- Modify `core/attributes/Attributes.cs`: append the new `AttributeType` values after the original five stat values so existing GDScript constants for `0..4` remain stable.
- Modify `resources/stats/StartingStats.cs`: add base/growth exports for max health, max energy, crit, evasion, lifesteal, and fixed/rate penetration.
- Modify `entities/components/AttributeComponent.cs`: expose the new effective attributes, initialize them from `StartingStats`, clamp them, and synchronize max health/energy to sibling vital components.
- Modify `entities/components/VitalComponentBase.cs`: make `Add` and `Subtract` return actual changed amount while preserving signals.
- Modify `entities/components/HealthComponent.cs`: make `TakeDamage` return actual damage.
- Modify `core/interfaces/IDamageable.cs`: update the damage contract to return actual damage.
- Modify `resources/monster/MonsterData.cs`: remove `MaxHealth` usage from the runtime contract after resource migration.
- Modify `entities/Monster.cs`: stop initializing health from `MonsterData.MaxHealth`; let `AttributeComponent` initialize health from `StartingStats`.
- Modify `core/application/EncounterMonsterScaler.cs`: scale `StartingStats.BaseMaxHealth` instead of `MonsterData.MaxHealth`.
- Modify `core/combat/DamageFormula.cs`: expand pure formula helpers for split penetration, evasion, crit, random variance, and lifesteal.
- Modify `entities/components/DamageReceiverComponent.cs`: add RNG/exported variance range, perform evasion/crit/random rolls, apply lifesteal from actual damage.
- Modify `core/ui/AttributeSummaryUI.cs`: keep the summary to five base stats, add a details popup button, and format full detail rows.
- Modify `scenes/inventory/AttributeSummaryUI.tscn`: replace direct penetration rows with a details button and popup panel.
- Modify `tests/CUSGA.Tests/Program.cs`: add focused tests for attributes, vitals, formula, scaler, and UI formatting helpers where practical.
- Modify resource files that still set `MonsterData.MaxHealth`: migrate values into embedded `StartingStats.BaseMaxHealth` and remove the old `MaxHealth` assignment.

---

### Task 1: Expand Attribute Schema

**Files:**
- Modify: `core/attributes/Attributes.cs`
- Modify: `resources/stats/StartingStats.cs`
- Modify: `tests/CUSGA.Tests/Program.cs`

- [ ] **Step 1: Write failing tests for new attribute enum and starting stats defaults**

Add this call near the other top-level test calls in `tests/CUSGA.Tests/Program.cs`:

```csharp
tests.StartingStatsExposeCombatExpansionDefaults();
```

Add this method inside `TerrainRandomizationTests`:

```csharp
/// <summary>
/// 验证新增战斗属性维度拥有明确默认值，并且基础五维枚举序号保持稳定。
/// </summary>
public void StartingStatsExposeCombatExpansionDefaults()
{
    Assert.Equal(0, (int)AttributeType.PhysAtk);
    Assert.Equal(1, (int)AttributeType.PhysDef);
    Assert.Equal(2, (int)AttributeType.MagPower);
    Assert.Equal(3, (int)AttributeType.MagResist);
    Assert.Equal(4, (int)AttributeType.Speed);

    var stats = new StartingStats();

    Assert.Approximately(1000f, stats.BaseMaxHealth);
    Assert.Approximately(0f, stats.MaxHealthGrowth);
    Assert.Approximately(100f, stats.BaseMaxEnergy);
    Assert.Approximately(0f, stats.MaxEnergyGrowth);
    Assert.Approximately(0f, stats.BaseCritRate);
    Assert.Approximately(0f, stats.CritRateGrowth);
    Assert.Approximately(1.5f, stats.BaseCritDamage);
    Assert.Approximately(0f, stats.CritDamageGrowth);
    Assert.Approximately(0f, stats.BaseEvasionRate);
    Assert.Approximately(0f, stats.EvasionRateGrowth);
    Assert.Approximately(0f, stats.BaseLifestealRate);
    Assert.Approximately(0f, stats.LifestealRateGrowth);
    Assert.Approximately(0f, stats.BaseFixedPhysPenetration);
    Assert.Approximately(0f, stats.FixedPhysPenetrationGrowth);
    Assert.Approximately(0f, stats.BasePhysPenetrationRate);
    Assert.Approximately(0f, stats.PhysPenetrationRateGrowth);
    Assert.Approximately(0f, stats.BaseFixedMagicPenetration);
    Assert.Approximately(0f, stats.FixedMagicPenetrationGrowth);
    Assert.Approximately(0f, stats.BaseMagicPenetrationRate);
    Assert.Approximately(0f, stats.MagicPenetrationRateGrowth);
}
```

- [ ] **Step 2: Run test build and verify failure**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build fails because `StartingStats` does not contain the new properties and `AttributeType` does not contain the new enum members.

- [ ] **Step 3: Replace `AttributeType` with the expanded enum**

In `core/attributes/Attributes.cs`, replace the enum with:

```csharp
public enum AttributeType
{
    PhysAtk,  // 物攻
    PhysDef,  // 物抗
    MagPower, // 法强
    MagResist,// 法抗
    Speed,    // 速度
    MaxHealth, // 生命上限
    MaxEnergy, // 能量上限
    FixedPhysPenetration, // 固定物理穿透
    PhysPenetrationRate, // 物理穿透率
    FixedMagicPenetration, // 固定法术穿透
    MagicPenetrationRate, // 法术穿透率
    CritRate, // 暴击率
    CritDamage, // 暴击总倍率
    EvasionRate, // 闪避率
    LifestealRate // 吸血率
}
```

- [ ] **Step 4: Add `StartingStats` properties**

In `resources/stats/StartingStats.cs`, update the class summary from “五维” to “战斗初始属性”, then add these exported properties after `SpeedGrowth`:

```csharp
    /// <summary>
    /// 获取或设置基础生命上限。
    /// </summary>
    [Export] public float BaseMaxHealth { get; set; } = 1000f;

    /// <summary>
    /// 获取或设置每级生命上限成长值。
    /// </summary>
    [Export] public float MaxHealthGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础能量上限；没有能量组件的单位会忽略该值。
    /// </summary>
    [Export] public float BaseMaxEnergy { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级能量上限成长值。
    /// </summary>
    [Export] public float MaxEnergyGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础固定物理穿透。
    /// </summary>
    [Export] public float BaseFixedPhysPenetration { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级固定物理穿透成长值。
    /// </summary>
    [Export] public float FixedPhysPenetrationGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础物理穿透率。
    /// </summary>
    [Export] public float BasePhysPenetrationRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级物理穿透率成长值。
    /// </summary>
    [Export] public float PhysPenetrationRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础固定法术穿透。
    /// </summary>
    [Export] public float BaseFixedMagicPenetration { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级固定法术穿透成长值。
    /// </summary>
    [Export] public float FixedMagicPenetrationGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础法术穿透率。
    /// </summary>
    [Export] public float BaseMagicPenetrationRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级法术穿透率成长值。
    /// </summary>
    [Export] public float MagicPenetrationRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础暴击率。
    /// </summary>
    [Export] public float BaseCritRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级暴击率成长值。
    /// </summary>
    [Export] public float CritRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础暴击总倍率。
    /// </summary>
    [Export] public float BaseCritDamage { get; set; } = 1.5f;

    /// <summary>
    /// 获取或设置每级暴击总倍率成长值。
    /// </summary>
    [Export] public float CritDamageGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础闪避率。
    /// </summary>
    [Export] public float BaseEvasionRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级闪避率成长值。
    /// </summary>
    [Export] public float EvasionRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础吸血率。
    /// </summary>
    [Export] public float BaseLifestealRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级吸血率成长值。
    /// </summary>
    [Export] public float LifestealRateGrowth { get; set; } = 0f;
```

- [ ] **Step 5: Run test build and verify pass for this task**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds unless later tasks have already introduced failing tests.

- [ ] **Step 6: Commit**

```bash
git add core/attributes/Attributes.cs resources/stats/StartingStats.cs tests/CUSGA.Tests/Program.cs
git commit -m "feat: expand combat attribute schema"
```

---

### Task 2: Initialize Runtime Attributes and Sync Vitals

**Files:**
- Modify: `entities/components/AttributeComponent.cs`
- Modify: `tests/CUSGA.Tests/Program.cs`

- [ ] **Step 1: Write failing tests for `AttributeComponent` initialization**

Replace the existing `AttributeComponentInitializesPenetrationAttributes` test call with:

```csharp
tests.AttributeComponentInitializesExpandedCombatAttributes();
tests.AttributeComponentSynchronizesHealthAndEnergyMaxima();
tests.AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent();
```

Replace the old `AttributeComponentInitializesPenetrationAttributes` method with:

```csharp
/// <summary>
/// 验证运行时属性组件初始化全部新增战斗属性维度。
/// </summary>
public void AttributeComponentInitializesExpandedCombatAttributes()
{
    var attributes = new AttributeComponent();
    var stats = new StartingStats
    {
        BaseMaxHealth = 1200f,
        BaseMaxEnergy = 80f,
        BaseFixedPhysPenetration = 18f,
        BasePhysPenetrationRate = 0.3f,
        BaseFixedMagicPenetration = 12f,
        BaseMagicPenetrationRate = 0.25f,
        BaseCritRate = 0.2f,
        BaseCritDamage = 1.75f,
        BaseEvasionRate = 0.1f,
        BaseLifestealRate = 0.15f
    };

    attributes.InitializeWithData(stats);

    Assert.Approximately(1200f, attributes.MaxHealth);
    Assert.Approximately(80f, attributes.MaxEnergy);
    Assert.Approximately(18f, attributes.FixedPhysPenetration);
    Assert.Approximately(0.3f, attributes.PhysPenetrationRate);
    Assert.Approximately(12f, attributes.FixedMagicPenetration);
    Assert.Approximately(0.25f, attributes.MagicPenetrationRate);
    Assert.Approximately(0.2f, attributes.CritRate);
    Assert.Approximately(1.75f, attributes.CritDamage);
    Assert.Approximately(0.1f, attributes.EvasionRate);
    Assert.Approximately(0.15f, attributes.LifestealRate);
}

/// <summary>
/// 验证生命上限和能量上限由属性组件初始化并同步到同宿主资源组件。
/// </summary>
public void AttributeComponentSynchronizesHealthAndEnergyMaxima()
{
    var owner = new Node { Name = "Components" };
    var health = new HealthComponent { Name = "HealthComponent" };
    var energy = new EnergyComponent { Name = "EnergyComponent" };
    var attributes = new AttributeComponent { Name = "AttributeComponent" };
    owner.AddChild(health);
    owner.AddChild(energy);
    owner.AddChild(attributes);

    attributes.InitializeWithData(new StartingStats
    {
        BaseMaxHealth = 1350f,
        BaseMaxEnergy = 90f
    });

    Assert.Equal(1350, health.MaxValue);
    Assert.Equal(1350, health.CurrentValue);
    Assert.Equal(90, energy.MaxValue);
    Assert.Equal(90, energy.CurrentValue);
}

/// <summary>
/// 验证没有能量组件的单位仍然可以初始化属性。
/// </summary>
public void AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent()
{
    var owner = new Node { Name = "Components" };
    var health = new HealthComponent { Name = "HealthComponent" };
    var attributes = new AttributeComponent { Name = "AttributeComponent" };
    owner.AddChild(health);
    owner.AddChild(attributes);

    attributes.InitializeWithData(new StartingStats
    {
        BaseMaxHealth = 777f,
        BaseMaxEnergy = 45f
    });

    Assert.Equal(777, health.MaxValue);
    Assert.Approximately(45f, attributes.MaxEnergy);
}
```

- [ ] **Step 2: Run test build and verify failure**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build fails because `AttributeComponent` does not expose the new properties.

- [ ] **Step 3: Add exported read-only properties to `AttributeComponent`**

In `entities/components/AttributeComponent.cs`, add public exported properties matching this pattern:

```csharp
    /// <summary>
    /// 获取当前生命上限。
    /// </summary>
    [Export]
    public float MaxHealth
    {
        get => GetEffectiveValue(AttributeType.MaxHealth);
        set { }
    }

    /// <summary>
    /// 获取当前能量上限。
    /// </summary>
    [Export]
    public float MaxEnergy
    {
        get => GetEffectiveValue(AttributeType.MaxEnergy);
        set { }
    }

    /// <summary>
    /// 获取当前固定物理穿透。
    /// </summary>
    [Export]
    public float FixedPhysPenetration
    {
        get => GetEffectiveValue(AttributeType.FixedPhysPenetration);
        set { }
    }

    /// <summary>
    /// 获取当前物理穿透率。
    /// </summary>
    [Export]
    public float PhysPenetrationRate
    {
        get => GetEffectiveValue(AttributeType.PhysPenetrationRate);
        set { }
    }

    /// <summary>
    /// 获取当前固定法术穿透。
    /// </summary>
    [Export]
    public float FixedMagicPenetration
    {
        get => GetEffectiveValue(AttributeType.FixedMagicPenetration);
        set { }
    }

    /// <summary>
    /// 获取当前法术穿透率。
    /// </summary>
    [Export]
    public float MagicPenetrationRate
    {
        get => GetEffectiveValue(AttributeType.MagicPenetrationRate);
        set { }
    }

    /// <summary>
    /// 获取当前暴击率。
    /// </summary>
    [Export]
    public float CritRate
    {
        get => GetEffectiveValue(AttributeType.CritRate);
        set { }
    }

    /// <summary>
    /// 获取当前暴击总倍率。
    /// </summary>
    [Export]
    public float CritDamage
    {
        get => GetEffectiveValue(AttributeType.CritDamage);
        set { }
    }

    /// <summary>
    /// 获取当前闪避率。
    /// </summary>
    [Export]
    public float EvasionRate
    {
        get => GetEffectiveValue(AttributeType.EvasionRate);
        set { }
    }

    /// <summary>
    /// 获取当前吸血率。
    /// </summary>
    [Export]
    public float LifestealRate
    {
        get => GetEffectiveValue(AttributeType.LifestealRate);
        set { }
    }
```

Remove the old `PhysPenetration` and `MagicPenetration` properties after their replacements compile.

- [ ] **Step 4: Update read-only inspector validation**

In `_ValidateProperty`, include all newly exported property names:

```csharp
            propName == nameof(MaxHealth) ||
            propName == nameof(MaxEnergy) ||
            propName == nameof(FixedPhysPenetration) ||
            propName == nameof(PhysPenetrationRate) ||
            propName == nameof(FixedMagicPenetration) ||
            propName == nameof(MagicPenetrationRate) ||
            propName == nameof(CritRate) ||
            propName == nameof(CritDamage) ||
            propName == nameof(EvasionRate) ||
            propName == nameof(LifestealRate))
```

- [ ] **Step 5: Initialize the new attributes**

In `InitializeWithData`, after the five base stat `SetAttribute` calls, use:

```csharp
        SetAttribute(AttributeType.MaxHealth, "生命上限", data.BaseMaxHealth, data.MaxHealthGrowth);
        SetAttribute(AttributeType.MaxEnergy, "能量上限", data.BaseMaxEnergy, data.MaxEnergyGrowth);
        SetAttribute(AttributeType.FixedPhysPenetration, "固定物理穿透", data.BaseFixedPhysPenetration, data.FixedPhysPenetrationGrowth);
        SetAttribute(AttributeType.PhysPenetrationRate, "物理穿透率", data.BasePhysPenetrationRate, data.PhysPenetrationRateGrowth);
        SetAttribute(AttributeType.FixedMagicPenetration, "固定法术穿透", data.BaseFixedMagicPenetration, data.FixedMagicPenetrationGrowth);
        SetAttribute(AttributeType.MagicPenetrationRate, "法术穿透率", data.BaseMagicPenetrationRate, data.MagicPenetrationRateGrowth);
        SetAttribute(AttributeType.CritRate, "暴击率", data.BaseCritRate, data.CritRateGrowth);
        SetAttribute(AttributeType.CritDamage, "暴击伤害", data.BaseCritDamage, data.CritDamageGrowth);
        SetAttribute(AttributeType.EvasionRate, "闪避率", data.BaseEvasionRate, data.EvasionRateGrowth);
        SetAttribute(AttributeType.LifestealRate, "吸血", data.BaseLifestealRate, data.LifestealRateGrowth);
```

- [ ] **Step 6: Add vital synchronization helper**

Add this private method to `AttributeComponent`:

```csharp
    private void SynchronizeVitalMaximum(AttributeType type)
    {
        if (Host == null)
        {
            return;
        }

        int maxValue = Mathf.Max(1, Mathf.RoundToInt(GetEffectiveValue(type)));

        switch (type)
        {
            case AttributeType.MaxHealth:
                Host.GetNodeOrNull<HealthComponent>("HealthComponent")
                    ?.InitializeMax(maxValue);
                break;

            case AttributeType.MaxEnergy:
                Host.GetNodeOrNull<EnergyComponent>("EnergyComponent")
                    ?.InitializeMax(maxValue);
                break;
        }
    }
```

Call it inside `RecalculateEffectiveAttribute` immediately after `_effectiveCache[type] = finalValue;` and before `if (!emitEvents)`:

```csharp
        SynchronizeVitalMaximum(type);
```

Because `InitializeWithData` calls `RecalculateAllDirect`, this also initializes vitals without a second code path.

- [ ] **Step 7: Update clamp rules**

Replace `ClampAttributeValue` cases with:

```csharp
            AttributeType.Speed => Mathf.Max(1f, value),

            AttributeType.MaxHealth or
            AttributeType.MaxEnergy => Mathf.Max(1f, value),

            AttributeType.PhysAtk or
            AttributeType.PhysDef or
            AttributeType.MagPower or
            AttributeType.MagResist or
            AttributeType.FixedPhysPenetration or
            AttributeType.FixedMagicPenetration => Mathf.Max(0f, value),

            AttributeType.PhysPenetrationRate or
            AttributeType.MagicPenetrationRate or
            AttributeType.CritRate or
            AttributeType.EvasionRate or
            AttributeType.LifestealRate => Mathf.Clamp(value, 0f, 1f),

            AttributeType.CritDamage => Mathf.Max(1f, value),
```

- [ ] **Step 8: Run test build**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds unless later tasks have introduced failing tests.

- [ ] **Step 9: Commit**

```bash
git add entities/components/AttributeComponent.cs tests/CUSGA.Tests/Program.cs
git commit -m "feat: initialize expanded combat attributes"
```

---

### Task 3: Return Actual Vital Changes

**Files:**
- Modify: `entities/components/VitalComponentBase.cs`
- Modify: `entities/components/HealthComponent.cs`
- Modify: `core/interfaces/IDamageable.cs`
- Modify: `tests/CUSGA.Tests/Program.cs`

- [ ] **Step 1: Write failing vital tests**

Add these calls near the top-level tests:

```csharp
tests.HealthComponentReturnsActualDamageTaken();
tests.VitalComponentBaseReturnsActualHealingAndLoss();
```

Add these methods to `TerrainRandomizationTests`:

```csharp
/// <summary>
/// 验证生命组件返回实际扣除生命，过量伤害不会被吸血错误放大。
/// </summary>
public void HealthComponentReturnsActualDamageTaken()
{
    var health = new HealthComponent();
    health.InitializeMax(30);

    int firstActual = health.TakeDamage(12, ElementType.None);
    int secondActual = health.TakeDamage(99, ElementType.None);

    Assert.Equal(12, firstActual);
    Assert.Equal(18, secondActual);
    Assert.Equal(0, health.CurrentValue);
}

/// <summary>
/// 验证资源基类返回实际变化量。
/// </summary>
public void VitalComponentBaseReturnsActualHealingAndLoss()
{
    var energy = new EnergyComponent();
    energy.InitializeMax(10);

    int consumed = energy.Subtract(7);
    int overConsumed = energy.Subtract(9);
    int restored = energy.Add(4);
    int overRestored = energy.Add(99);

    Assert.Equal(7, consumed);
    Assert.Equal(3, overConsumed);
    Assert.Equal(4, restored);
    Assert.Equal(6, overRestored);
    Assert.Equal(10, energy.CurrentValue);
}
```

- [ ] **Step 2: Run test build and verify failure**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build fails because `TakeDamage`, `Add`, and `Subtract` return `void`.

- [ ] **Step 3: Change `VitalComponentBase.Add` and `Subtract` return values**

In `VitalComponentBase`, replace the methods with:

```csharp
    public virtual int Add(int amount)
    {
        if (amount <= 0 || CurrentValue >= MaxValue)
        {
            return 0;
        }

        int oldValue = CurrentValue;
        CurrentValue = Mathf.Min(CurrentValue + amount, MaxValue);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
        return CurrentValue - oldValue;
    }

    public virtual int Subtract(int amount)
    {
        if (amount <= 0 || CurrentValue <= 0)
        {
            return 0;
        }

        int oldValue = CurrentValue;
        CurrentValue = Mathf.Max(CurrentValue - amount, 0);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);

        if (CurrentValue <= 0)
        {
            EmitSignal(SignalName.Depleted);
        }

        return oldValue - CurrentValue;
    }
```

- [ ] **Step 4: Change `HealthComponent.TakeDamage` return value**

Replace `TakeDamage` with:

```csharp
    public int TakeDamage(int amount, ElementType elementType)
    {
        int actualDamage = Subtract(amount);
        if (actualDamage > 0)
        {
            EmitSignal(SignalName.DamageTaken, actualDamage, (int)elementType);
        }

        return actualDamage;
    }
```

- [ ] **Step 5: Update `IDamageable`**

In `core/interfaces/IDamageable.cs`, change the interface to:

```csharp
using CUSGA.core.constants;

namespace CUSGA.core.interfaces;

public interface IDamageable
{
    int TakeDamage(int amount, ElementType elementType);
}
```

- [ ] **Step 6: Run test build**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add entities/components/VitalComponentBase.cs entities/components/HealthComponent.cs core/interfaces/IDamageable.cs tests/CUSGA.Tests/Program.cs
git commit -m "feat: return actual vital changes"
```

---

### Task 4: Expand Pure Damage Formula Helpers

**Files:**
- Modify: `core/combat/DamageFormula.cs`
- Modify: `tests/CUSGA.Tests/Program.cs`

- [ ] **Step 1: Replace old formula tests with expanded formula tests**

Update existing damage formula test calls to:

```csharp
tests.PhysicalDamageFormulaAppliesFixedAndRatePenetration();
tests.MagicDamageFormulaClampsOverPenetratedResistance();
tests.DamageFormulaResolvesEvasionCriticalVarianceAndLifesteal();
tests.DamageFormulaCalculatesActualDamageBeforeLifesteal();
```

Use these test methods:

```csharp
/// <summary>
/// 验证物理基础伤害使用同一个全局常数，并同时应用固定穿透和百分比穿透。
/// </summary>
public void PhysicalDamageFormulaAppliesFixedAndRatePenetration()
{
    float damage = DamageFormula.CalculatePhysicalBaseDamage(
        skillPower: 120f,
        attackerPhysAtk: 200f,
        defenderPhysDef: 300f,
        physicalPenetrationRate: 0.25f,
        fixedPhysicalPenetration: 25f
    );

    Assert.Approximately(120f, damage);
}

/// <summary>
/// 验证法术穿透过量时有效法抗不会低于 0。
/// </summary>
public void MagicDamageFormulaClampsOverPenetratedResistance()
{
    float damage = DamageFormula.CalculateMagicBaseDamage(
        skillPower: 60f,
        attackerMagPower: 200f,
        defenderMagResist: 120f,
        magicPenetrationRate: 1.5f,
        fixedMagicPenetration: 40f
    );

    Assert.Approximately(180f, damage);
}

/// <summary>
/// 验证闪避、暴击、随机浮动和吸血的纯公式入口。
/// </summary>
public void DamageFormulaResolvesEvasionCriticalVarianceAndLifesteal()
{
    Assert.True(DamageFormula.ShouldEvade(evasionRate: 0.3f, evasionRoll: 0.2f));
    Assert.False(DamageFormula.ShouldEvade(evasionRate: 0.3f, evasionRoll: 0.8f));
    Assert.True(DamageFormula.ShouldCrit(critRate: 0.4f, critRoll: 0.1f));
    Assert.False(DamageFormula.ShouldCrit(critRate: 0.4f, critRoll: 0.9f));
    Assert.Approximately(1.75f, DamageFormula.CalculateCriticalModifier(true, 1.75f));
    Assert.Approximately(1f, DamageFormula.CalculateCriticalModifier(false, 1.75f));
    Assert.Approximately(1.02f, DamageFormula.CalculateRandomVariance(0.95f, 1.05f, 0.7f));
    Assert.Equal(13, DamageFormula.CalculateLifestealAmount(51, 0.25f));
}

/// <summary>
/// 验证吸血使用实际扣血量，而不是取整后的理论伤害。
/// </summary>
public void DamageFormulaCalculatesActualDamageBeforeLifesteal()
{
    Assert.Equal(35, DamageFormula.CalculateActualDamage(finalDamage: 99, defenderCurrentHealth: 35));
    Assert.Equal(9, DamageFormula.CalculateLifestealAmount(finalActualDamage: 35, lifestealRate: 0.25f));
}
```

- [ ] **Step 2: Run test build and verify failure**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build fails because the new helper methods do not exist and existing damage methods still use old penetration names at call sites.

- [ ] **Step 3: Update `DamageFormula` methods**

In `core/combat/DamageFormula.cs`, keep the existing base damage methods and add:

```csharp
    /// <summary>
    /// 判断本次伤害是否被闪避。
    /// </summary>
    /// <param name="evasionRate">防御方闪避率。</param>
    /// <param name="evasionRoll">本次闪避随机值，范围为 0 到 1。</param>
    /// <returns>闪避成功返回 true。</returns>
    public static bool ShouldEvade(float evasionRate, float evasionRoll)
    {
        return Math.Clamp(evasionRoll, 0f, 1f) < Math.Clamp(evasionRate, 0f, 1f);
    }

    /// <summary>
    /// 判断本次伤害是否暴击。
    /// </summary>
    /// <param name="critRate">攻击方暴击率。</param>
    /// <param name="critRoll">本次暴击随机值，范围为 0 到 1。</param>
    /// <returns>暴击成功返回 true。</returns>
    public static bool ShouldCrit(float critRate, float critRoll)
    {
        return Math.Clamp(critRoll, 0f, 1f) < Math.Clamp(critRate, 0f, 1f);
    }

    /// <summary>
    /// 计算暴击修正倍率。
    /// </summary>
    /// <param name="isCritical">本次是否暴击。</param>
    /// <param name="critDamage">暴击总倍率。</param>
    /// <returns>返回本次暴击修正倍率。</returns>
    public static float CalculateCriticalModifier(bool isCritical, float critDamage)
    {
        return isCritical ? Math.Max(1f, critDamage) : 1f;
    }

    /// <summary>
    /// 根据随机浮动配置和随机值计算本次浮动系数。
    /// </summary>
    /// <param name="min">随机浮动最小值。</param>
    /// <param name="max">随机浮动最大值。</param>
    /// <param name="roll">本次随机值，范围为 0 到 1。</param>
    /// <returns>返回本次随机浮动系数。</returns>
    public static float CalculateRandomVariance(float min, float max, float roll)
    {
        float lower = Math.Max(0f, Math.Min(min, max));
        float upper = Math.Max(0f, Math.Max(min, max));
        float normalizedRoll = Math.Clamp(roll, 0f, 1f);
        return lower + (upper - lower) * normalizedRoll;
    }

    /// <summary>
    /// 根据理论最终伤害和防御方当前生命计算实际扣血。
    /// </summary>
    /// <param name="finalDamage">取整后的理论最终伤害。</param>
    /// <param name="defenderCurrentHealth">防御方当前生命。</param>
    /// <returns>返回实际扣除生命。</returns>
    public static int CalculateActualDamage(int finalDamage, int defenderCurrentHealth)
    {
        return Math.Max(0, Math.Min(finalDamage, Math.Max(0, defenderCurrentHealth)));
    }

    /// <summary>
    /// 根据最终实际伤害和吸血率计算吸血量。
    /// </summary>
    /// <param name="finalActualDamage">最终实际扣除生命。</param>
    /// <param name="lifestealRate">攻击方吸血率。</param>
    /// <returns>返回取整后的吸血量。</returns>
    public static int CalculateLifestealAmount(int finalActualDamage, float lifestealRate)
    {
        return Math.Max(0, (int)MathF.Round(
            Math.Max(0, finalActualDamage) * Math.Clamp(lifestealRate, 0f, 1f),
            MidpointRounding.AwayFromZero
        ));
    }
```

- [ ] **Step 4: Run test build**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add core/combat/DamageFormula.cs tests/CUSGA.Tests/Program.cs
git commit -m "feat: add pure damage resolution helpers"
```

---

### Task 5: Integrate Damage Receiver Runtime Resolution

**Files:**
- Modify: `entities/components/DamageReceiverComponent.cs`

- [ ] **Step 1: Run pre-change impact analysis**

Run GitNexus impact before editing:

```text
impact(target: "ReceiveDamage", file_path: "entities/components/DamageReceiverComponent.cs", kind: "Method", direction: "upstream", repo: "CUSGA")
impact(target: "DamageReceiverComponent", file_path: "entities/components/DamageReceiverComponent.cs", kind: "Class", direction: "upstream", repo: "CUSGA")
```

Expected: review risk level and stop for user warning if HIGH or CRITICAL.

- [ ] **Step 2: Add RNG and configurable random variance properties**

Add fields/properties inside `DamageReceiverComponent`:

```csharp
    private readonly RandomNumberGenerator _rng = new();

    /// <summary>
    /// 获取或设置随机伤害浮动下限。
    /// </summary>
    [Export] public float RandomVarianceMin { get; set; } = 0.95f;

    /// <summary>
    /// 获取或设置随机伤害浮动上限。
    /// </summary>
    [Export] public float RandomVarianceMax { get; set; } = 1.05f;
```

Add `_Ready`:

```csharp
    public override void _Ready()
    {
        _rng.Randomize();
    }
```

- [ ] **Step 3: Replace base damage calls with split penetration**

In `CalculateBaseDamage`, update physical and magic calls to:

```csharp
            DamageType.Physical => DamageFormula.CalculatePhysicalBaseDamage(
                skillPower,
                attackerStats?.PhysAtk ?? 0f,
                defenderStats?.PhysDef ?? 0f,
                attackerStats?.PhysPenetrationRate ?? 0f,
                attackerStats?.FixedPhysPenetration ?? 0f
            ),
            DamageType.Magic => DamageFormula.CalculateMagicBaseDamage(
                skillPower,
                attackerStats?.MagPower ?? 0f,
                defenderStats?.MagResist ?? 0f,
                attackerStats?.MagicPenetrationRate ?? 0f,
                attackerStats?.FixedMagicPenetration ?? 0f
            ),
```

- [ ] **Step 4: Apply evasion before base damage**

At the start of `ReceiveDamage`, after component lookups and before `CalculateBaseDamage`, add:

```csharp
        if (DamageFormula.ShouldEvade(defenderStats?.EvasionRate ?? 0f, _rng.Randf()))
        {
            GD.Print(
                $"[Damage] Target: {defender.GetParent().Name} | " +
                $"Source: {payload.Source?.Name ?? "Unknown"} | " +
                $"Damage: 0 | Evaded | " +
                $"Element: {payload.Element} | " +
                $"Type: {payload.Type}"
            );
            return;
        }
```

- [ ] **Step 5: Apply crit and random variance in order**

After `float damage = CalculateBaseDamage(...)`, add:

```csharp
        bool isCritical = DamageFormula.ShouldCrit(attackerStats?.CritRate ?? 0f, _rng.Randf());
        damage *= DamageFormula.CalculateCriticalModifier(
            isCritical,
            attackerStats?.CritDamage ?? 1f
        );
```

After `ApplyElementMultiplier(payload, defender, ref damage);`, add:

```csharp
        damage *= DamageFormula.CalculateRandomVariance(
            RandomVarianceMin,
            RandomVarianceMax,
            _rng.Randf()
        );
```

Keep the existing status hooks in their current relative order.

- [ ] **Step 6: Use actual damage for lifesteal**

Replace the final damage application block with:

```csharp
        int finalDamage = Mathf.Max(0, Mathf.RoundToInt(damage));
        var defenderHealth = defender.GetNodeOrNull<HealthComponent>("HealthComponent");
        int actualDamage = defenderHealth?.TakeDamage(finalDamage, payload.Element) ?? 0;

        int lifestealAmount = DamageFormula.CalculateLifestealAmount(
            actualDamage,
            attackerStats?.LifestealRate ?? 0f
        );

        if (lifestealAmount > 0)
        {
            payload.Source?.GetNodeOrNull<HealthComponent>("HealthComponent")
                ?.Add(lifestealAmount);
        }

        GD.Print(
            $"[Damage] Target: {defender.GetParent().Name} | " +
            $"Source: {payload.Source?.Name ?? "Unknown"} | " +
            $"Damage: {actualDamage} | " +
            $"Critical: {isCritical} | " +
            $"Lifesteal: {lifestealAmount} | " +
            $"Element: {payload.Element} | " +
            $"Type: {payload.Type}"
        );
```

Remove the old `TakeDamage` call after the log so damage is not applied twice.

- [ ] **Step 7: Build**

Run:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add entities/components/DamageReceiverComponent.cs
git commit -m "feat: resolve crit evasion variance and lifesteal"
```

---

### Task 6: Migrate Monster Max Health to StartingStats

**Files:**
- Modify: `resources/monster/MonsterData.cs`
- Modify: `entities/Monster.cs`
- Modify: `core/application/EncounterMonsterScaler.cs`
- Modify: `tests/CUSGA.Tests/Program.cs`
- Modify: monster scene/resource files that currently assign `MaxHealth`

- [ ] **Step 1: Write failing scaler test**

In `EncounterMonsterScalerDuplicatesAndScalesAllEncounterStats`, remove `monster.MaxHealth = 100;` and add:

```csharp
        baseStats.BaseMaxHealth = 100f;
```

Change assertions:

```csharp
        Assert.Approximately(180f, scaledMonster.InitialAttributes.BaseMaxHealth);
        Assert.Approximately(100f, baseStats.BaseMaxHealth);
```

Remove assertions that read `scaledMonster.MaxHealth` and `monster.MaxHealth`.

- [ ] **Step 2: Run test build and verify failure**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build fails until scaler updates `BaseMaxHealth`.

- [ ] **Step 3: Update `EncounterMonsterScaler`**

In `ScaleMonster`, remove:

```csharp
        scaled.MaxHealth = ScaleInt(source.MaxHealth, terrain.MaxHealth, day.MaxHealth);
```

In `ScaleStats`, add before `return scaled;`:

```csharp
        scaled.BaseMaxHealth = ScaleFloat(source.BaseMaxHealth, terrain.MaxHealth, day.MaxHealth);
        scaled.MaxHealthGrowth = source.MaxHealthGrowth;
        scaled.BaseMaxEnergy = source.BaseMaxEnergy;
        scaled.MaxEnergyGrowth = source.MaxEnergyGrowth;
```

- [ ] **Step 4: Update `Monster.Initialize`**

Remove:

```csharp
        Health.InitializeMax(data.MaxHealth);
```

The existing `Attributes.InitializeWithData(data.InitialAttributes);` call must remain before UI updates so `AttributeComponent` synchronizes health.

- [ ] **Step 5: Remove `MonsterData.MaxHealth` from C#**

In `resources/monster/MonsterData.cs`, remove:

```csharp
    [Export] public int MaxHealth { get; set; }
```

- [ ] **Step 6: Migrate monster resources**

Search:

```bash
rg -n "MaxHealth =" scenes resources items
```

For every `MonsterData` resource assignment such as:

```text
MaxHealth = 100
```

set the associated `StartingStats` sub-resource to:

```text
BaseMaxHealth = 100.0
```

and remove the `MaxHealth = ...` line. For `scenes/monster_scenes/monster.tscn`, the embedded `Resource_4jp6m` is the monster's `InitialAttributes`; add `BaseMaxHealth = 100.0` to that sub-resource and remove the later `MaxHealth = 100`.

- [ ] **Step 7: Run build**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
env CI=true dotnet build CUSGA.sln --no-restore
```

Expected: both builds succeed.

- [ ] **Step 8: Commit**

```bash
git add resources/monster/MonsterData.cs entities/Monster.cs core/application/EncounterMonsterScaler.cs tests/CUSGA.Tests/Program.cs scenes resources
git commit -m "feat: move monster max health into starting stats"
```

---

### Task 7: Update Attribute Summary UI and Detail Popup

**Files:**
- Modify: `core/ui/AttributeSummaryUI.cs`
- Modify: `scenes/inventory/AttributeSummaryUI.tscn`

- [ ] **Step 1: Run pre-change impact analysis**

Run:

```text
impact(target: "AttributeSummaryUI", file_path: "core/ui/AttributeSummaryUI.cs", kind: "Class", direction: "upstream", repo: "CUSGA")
impact(target: "Refresh", file_path: "core/ui/AttributeSummaryUI.cs", kind: "Method", direction: "upstream", repo: "CUSGA")
```

Expected: review risk level and stop for user warning if HIGH or CRITICAL.

- [ ] **Step 2: Update summary fields**

In `AttributeSummaryUI.cs`, remove `_physPenetrationValue` and `_magicPenetrationValue`, then add fields:

```csharp
    private Button _detailsButton = null!;
    private PopupPanel _detailsPopup = null!;
    private GridContainer _detailsGrid = null!;
```

In `_Ready`, keep the five base labels and add:

```csharp
        _detailsButton = GetNode<Button>("%DetailsButton");
        _detailsPopup = GetNode<PopupPanel>("%DetailsPopup");
        _detailsGrid = GetNode<GridContainer>("%DetailsGrid");
        _detailsButton.Pressed += ShowDetailsPopup;
```

In `_ExitTree`, add:

```csharp
        if (_detailsButton != null)
        {
            _detailsButton.Pressed -= ShowDetailsPopup;
        }
```

- [ ] **Step 3: Keep `Refresh` to five base stats**

Update `Refresh` to only set:

```csharp
        SetValue(_physAtkValue, AttributeType.PhysAtk);
        SetValue(_physDefValue, AttributeType.PhysDef);
        SetValue(_magPowerValue, AttributeType.MagPower);
        SetValue(_magResistValue, AttributeType.MagResist);
        SetValue(_speedValue, AttributeType.Speed);
```

- [ ] **Step 4: Add popup formatting helpers**

Add:

```csharp
    private void ShowDetailsPopup()
    {
        RefreshDetails();
        _detailsPopup.PopupCentered();
    }

    private void RefreshDetails()
    {
        SetDetailValue("MaxHealthDetailValue", AttributeType.MaxHealth);
        SetDetailValue("MaxEnergyDetailValue", AttributeType.MaxEnergy);
        SetDetailPenetration(
            "PhysPenetrationDetailValue",
            AttributeType.FixedPhysPenetration,
            AttributeType.PhysPenetrationRate
        );
        SetDetailPenetration(
            "MagicPenetrationDetailValue",
            AttributeType.FixedMagicPenetration,
            AttributeType.MagicPenetrationRate
        );
        SetDetailPercent("CritRateDetailValue", AttributeType.CritRate);
        SetDetailPercent("CritDamageDetailValue", AttributeType.CritDamage);
        SetDetailPercent("EvasionRateDetailValue", AttributeType.EvasionRate);
        SetDetailPercent("LifestealRateDetailValue", AttributeType.LifestealRate);
    }

    private void SetDetailValue(string nodeName, AttributeType type)
    {
        GetNode<Label>($"%{nodeName}").Text = _attributes == null
            ? "-"
            : FormatNumber(_attributes.GetEffectiveValue(type));
    }

    private void SetDetailPercent(string nodeName, AttributeType type)
    {
        GetNode<Label>($"%{nodeName}").Text = _attributes == null
            ? "-"
            : FormatPercent(_attributes.GetEffectiveValue(type));
    }

    private void SetDetailPenetration(
        string nodeName,
        AttributeType fixedType,
        AttributeType rateType
    )
    {
        GetNode<Label>($"%{nodeName}").Text = _attributes == null
            ? "-"
            : $"{FormatNumber(_attributes.GetEffectiveValue(fixedType))} | {FormatPercent(_attributes.GetEffectiveValue(rateType))}";
    }

    private static string FormatPercent(float value)
    {
        return $"{value * 100f:0.#}%";
    }
```

Change `SetPercentValue` to call `FormatPercent`.

- [ ] **Step 5: Update scene summary rows**

In `scenes/inventory/AttributeSummaryUI.tscn`, remove the current `PhysPenetrationLabel`, `PhysPenetrationValue`, `MagicPenetrationLabel`, and `MagicPenetrationValue` nodes from the summary grid.

Add a button under `AttributeGrid`:

```text
[node name="DetailsButton" type="Button" parent="VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
text = "详情"
```

- [ ] **Step 6: Add details popup to scene**

Add a popup under the root:

```text
[node name="DetailsPopup" type="PopupPanel" parent="."]
unique_name_in_owner = true
title = "详细属性"

[node name="MarginContainer" type="MarginContainer" parent="DetailsPopup"]
layout_mode = 2
theme_override_constants/margin_left = 10
theme_override_constants/margin_top = 10
theme_override_constants/margin_right = 10
theme_override_constants/margin_bottom = 10

[node name="DetailsGrid" type="GridContainer" parent="DetailsPopup/MarginContainer"]
unique_name_in_owner = true
layout_mode = 2
columns = 2
```

Inside `DetailsGrid`, add label/value pairs with unique value node names:

```text
MaxHealthDetailValue
MaxEnergyDetailValue
PhysPenetrationDetailValue
MagicPenetrationDetailValue
CritRateDetailValue
CritDamageDetailValue
EvasionRateDetailValue
LifestealRateDetailValue
```

Use Chinese labels: `生命上限`, `能量上限`, `物理穿透`, `法术穿透`, `暴击率`, `暴击伤害`, `闪避率`, `吸血`.

- [ ] **Step 7: Build and scene smoke**

Run:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
godot-mono --headless --path . --build-solutions --quit
godot-mono --headless --path . --scene res://scenes/inventory/AttributeSummaryUI.tscn --quit-after 5
```

Expected: build succeeds and scene exits 0. Existing unrelated item UID warnings are acceptable only if they do not reference touched files.

- [ ] **Step 8: Commit**

```bash
git add core/ui/AttributeSummaryUI.cs scenes/inventory/AttributeSummaryUI.tscn
git commit -m "feat: add detailed attribute popup"
```

---

### Task 8: Update Godot/GDScript Enum References and Scene Metadata

**Files:**
- Modify: `scripts/card_scripts/monster_attribute.gd`
- Modify: `scripts/battle_scripts/player_attribute.gd`
- Modify: relevant `.tscn` files generated or adjusted by Godot

- [ ] **Step 1: Confirm base enum indexes remain stable**

Open both GDScript files and confirm these constants remain correct:

```gdscript
const ATTRIBUTE_TYPE_PHYS_ATK: int = 0
const ATTRIBUTE_TYPE_PHYS_DEF: int = 1
const ATTRIBUTE_TYPE_MAG_POWER: int = 2
const ATTRIBUTE_TYPE_MAG_RESIST: int = 3
const ATTRIBUTE_TYPE_SPEED: int = 4
```

Expected: no code change needed if Task 1 appended new enum values after `Speed`.

- [ ] **Step 2: Run Godot global class refresh**

Run:

```bash
godot-mono --headless --path . --build-solutions --quit
```

Expected: command exits 0. Keep any newly generated `.cs.uid` files for new C# scripts if Godot creates them.

- [ ] **Step 3: Smoke main and touched scenes**

Run:

```bash
godot-mono --headless --path . --scene res://scenes/main_menu_scenes/main_menu.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/inventory/AttributeSummaryUI.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/monster_scenes/monster.tscn --quit-after 5
```

Expected: commands exit 0. Treat `SCRIPT ERROR`, `Parse Error`, `Failed to load script`, and C# build failures as blockers.

- [ ] **Step 4: Commit**

```bash
git add scripts/card_scripts/monster_attribute.gd scripts/battle_scripts/player_attribute.gd scenes .godot core resources
git commit -m "chore: refresh godot combat attribute metadata"
```

---

### Task 9: Final Verification and Change Scope Review

**Files:**
- Review all modified files

- [ ] **Step 1: Run full compile checks**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
env CI=true dotnet build CUSGA.sln --no-restore
```

Expected: both builds succeed with 0 errors.

- [ ] **Step 2: Run Godot integration checks**

Run:

```bash
godot-mono --headless --path . --build-solutions --quit
godot-mono --headless --path . --scene res://scenes/main_menu_scenes/main_menu.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/inventory/AttributeSummaryUI.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/monster_scenes/monster.tscn --quit-after 5
```

Expected: all commands exit 0.

- [ ] **Step 3: Run GitNexus change detection**

Run:

```text
detect_changes(repo: "CUSGA", scope: "all")
```

Expected: affected processes include combat damage, attribute recalculation, inventory attribute UI, monster initialization, and encounter scaling. Investigate any unrelated modules.

- [ ] **Step 4: Search for removed names**

Run:

```bash
rg -n "PhysPenetration\\b|MagicPenetration\\b|PhysDamageBoost|MagicDamageBoost|MaxHealth =" core entities resources scripts scenes tests
```

Expected:
- No `PhysDamageBoost` or `MagicDamageBoost`.
- No old unsplit `PhysPenetration` or `MagicPenetration` property names.
- No `MonsterData` resource assignment using `MaxHealth =`.

- [ ] **Step 5: Review diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: diff is scoped to combat attributes, vitals, damage resolution, monster max health migration, and attribute UI. `git diff --check` exits 0.

- [ ] **Step 6: Final commit if previous tasks were not committed individually**

If earlier task commits were skipped, commit all remaining implementation changes:

```bash
git add core entities resources scripts scenes tests CONTEXT.md docs/superpowers/specs/2026-05-27-combat-attribute-expansion-design.md docs/superpowers/plans/2026-05-27-combat-attribute-expansion.md
git commit -m "feat: expand combat attributes and damage resolution"
```
