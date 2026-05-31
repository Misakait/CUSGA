# Fix Vital Max Sync Review Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复属性重算导致生命/能量被隐式回满的问题，并补上能防止该回归的测试。

**Architecture:** `VitalComponentBase` 拆分“首次初始化到满值”和“后续仅同步上限”的语义。`AttributeComponent` 在 `AttributeChangeReason.Initialization` 时仍调用初始化路径，其他重算路径只更新上限并保留当前值，避免 UI 读取、状态变化、装备变化等属性重算产生隐式治疗。

**Tech Stack:** Godot 4.6 Mono, C#, `env CI=true dotnet build`, `godot-mono --headless`, GitNexus impact/detect changes.

---

## File Structure

- Modify: `entities/components/VitalComponentBase.cs`
  - Add a public method for changing `MaxValue` while preserving `CurrentValue`.
  - Keep `InitializeMax()` as the explicit “set max and refill to full” initialization API.
- Modify: `entities/components/AttributeComponent.cs`
  - Pass `AttributeChangeReason` into vital maximum synchronization.
  - Use refill only for `AttributeChangeReason.Initialization`; use preserve-current sync for every other recalculation.
  - Remove side effects from lazy `GetEffectiveValue()` reads for max-health/max-energy synchronization.
- Modify: `tests/CUSGA.Tests/Program.cs`
  - Add focused tests proving recalculation does not heal/refill.
  - Add focused tests proving max shrink clamps current value and max increase preserves current value.

---

### Task 1: Add Regression Tests For Preserve-Current Vital Sync

**Files:**
- Modify: `tests/CUSGA.Tests/Program.cs`

- [ ] **Step 1: Run impact checks before touching test-facing production symbols**

Use GitNexus MCP impact analysis before edits:

```text
impact(repo: "CUSGA", target: "SynchronizeVitalMaximum", file_path: "entities/components/AttributeComponent.cs", direction: "upstream", maxDepth: 3)
impact(repo: "CUSGA", target: "InitializeMax", file_path: "entities/components/VitalComponentBase.cs", direction: "upstream", maxDepth: 3)
impact(repo: "CUSGA", target: "ForceRecalculateAll", file_path: "entities/components/AttributeComponent.cs", direction: "upstream", maxDepth: 3)
```

Expected: `SynchronizeVitalMaximum` may not exist in the stale index if it is newly added; if so, continue with `AttributeComponent`/`InitializeMax` impact results and note the index limitation.

- [ ] **Step 2: Add test calls near the existing attribute/vital tests**

In `tests/CUSGA.Tests/Program.cs`, add these calls after `tests.AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent();`:

```csharp
tests.AttributeComponentPreservesCurrentVitalsOnUnchangedRecalculation();
tests.AttributeComponentPreservesCurrentVitalsWhenMaximaIncrease();
tests.AttributeComponentClampsCurrentVitalsWhenMaximaShrink();
```

- [ ] **Step 3: Add failing tests**

Add these methods inside `TerrainRandomizationTests`, immediately after `AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent()`:

```csharp
/// <summary>
/// 验证普通属性重算不会把生命和能量隐式回满。
/// </summary>
public void AttributeComponentPreservesCurrentVitalsOnUnchangedRecalculation()
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
        BaseMaxHealth = 100f,
        BaseMaxEnergy = 50f
    });
    health.TakeDamage(30, ElementType.None);
    energy.Subtract(20);

    attributes.ForceRecalculateAll(owner);

    Assert.Equal(100, health.MaxValue);
    Assert.Equal(70, health.CurrentValue);
    Assert.Equal(50, energy.MaxValue);
    Assert.Equal(30, energy.CurrentValue);
}

/// <summary>
/// 验证生命和能量上限提高时不会额外治疗当前值。
/// </summary>
public void AttributeComponentPreservesCurrentVitalsWhenMaximaIncrease()
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
        BaseMaxHealth = 100f,
        BaseMaxEnergy = 50f
    });
    health.TakeDamage(30, ElementType.None);
    energy.Subtract(20);

    attributes.AddPermanentBonus(AttributeType.MaxHealth, 40f, owner);
    attributes.AddPermanentBonus(AttributeType.MaxEnergy, 10f, owner);

    Assert.Equal(140, health.MaxValue);
    Assert.Equal(70, health.CurrentValue);
    Assert.Equal(60, energy.MaxValue);
    Assert.Equal(30, energy.CurrentValue);
}

/// <summary>
/// 验证生命和能量上限降低时当前值会被钳制到新上限，但不会回满。
/// </summary>
public void AttributeComponentClampsCurrentVitalsWhenMaximaShrink()
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
        BaseMaxHealth = 100f,
        BaseMaxEnergy = 50f
    });
    health.TakeDamage(10, ElementType.None);
    energy.Subtract(5);

    attributes.AddPermanentBonus(AttributeType.MaxHealth, -30f, owner);
    attributes.AddPermanentBonus(AttributeType.MaxEnergy, -20f, owner);

    Assert.Equal(70, health.MaxValue);
    Assert.Equal(70, health.CurrentValue);
    Assert.Equal(30, energy.MaxValue);
    Assert.Equal(30, energy.CurrentValue);
}
```

- [ ] **Step 4: Build to verify the regression tests compile**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds. These tests may not be executable through plain `dotnet run` because this project needs the Godot runtime for `GodotSharp`; do not use plain `dotnet run` as the primary runtime verdict.

---

### Task 2: Split Vital Initialization From Preserve-Current Max Sync

**Files:**
- Modify: `entities/components/VitalComponentBase.cs`
- Modify: `entities/components/AttributeComponent.cs`

- [ ] **Step 1: Add preserve-current max setter**

In `entities/components/VitalComponentBase.cs`, add this method immediately after `InitializeMax()`:

```csharp
/// <summary>
/// 更新资源上限并保留当前值，只在当前值超过新上限时进行钳制。
/// </summary>
/// <param name="newMaxValue">新的资源上限，低于 1 时按 1 处理。</param>
public virtual void SetMaxValuePreservingCurrent(int newMaxValue)
{
    int normalizedMaxValue = Mathf.Max(1, newMaxValue);
    int oldMaxValue = MaxValue;
    int oldCurrentValue = CurrentValue;

    MaxValue = normalizedMaxValue;
    CurrentValue = Mathf.Clamp(CurrentValue, 0, MaxValue);

    if (oldMaxValue != MaxValue || oldCurrentValue != CurrentValue)
    {
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
    }
}
```

- [ ] **Step 2: Remove vital side effects from lazy attribute reads**

In `entities/components/AttributeComponent.cs`, update `GetEffectiveValue()` so it only caches and returns:

```csharp
public float GetEffectiveValue(AttributeType type)
{
    if (_effectiveCache.TryGetValue(type, out var value))
    {
        return value;
    }

    float calculated = CalculateUnclampedEffectiveValue(type);
    float clamped = ClampAttributeValue(type, calculated);

    _effectiveCache[type] = clamped;
    return clamped;
}
```

- [ ] **Step 3: Pass recalculation reason into vital sync**

In `RecalculateEffectiveAttribute()`, replace each existing call:

```csharp
SynchronizeVitalMaximum(type, oldValue);
SynchronizeVitalMaximum(type, finalValue);
```

with:

```csharp
SynchronizeVitalMaximum(type, oldValue, reason);
SynchronizeVitalMaximum(type, finalValue, reason);
```

- [ ] **Step 4: Update the sync method implementation**

Replace the current `SynchronizeVitalMaximum` method in `entities/components/AttributeComponent.cs` with:

```csharp
private void SynchronizeVitalMaximum(AttributeType type, float value, AttributeChangeReason reason)
{
    int maxValue = Mathf.Max(1, Mathf.RoundToInt(value));
    bool shouldRefill = reason == AttributeChangeReason.Initialization;

    switch (type)
    {
        case AttributeType.MaxHealth:
            SynchronizeVitalMaximum(
                Host?.GetNodeOrNull<HealthComponent>("HealthComponent"),
                maxValue,
                shouldRefill
            );
            break;

        case AttributeType.MaxEnergy:
            // 怪物等无能量单位不会挂载 EnergyComponent；这里允许缺失。
            SynchronizeVitalMaximum(
                Host?.GetNodeOrNull<EnergyComponent>("EnergyComponent"),
                maxValue,
                shouldRefill
            );
            break;
    }
}

private static void SynchronizeVitalMaximum(
    VitalComponentBase vital,
    int maxValue,
    bool shouldRefill
)
{
    if (vital == null)
    {
        return;
    }

    if (shouldRefill)
    {
        vital.InitializeMax(maxValue);
        return;
    }

    vital.SetMaxValuePreservingCurrent(maxValue);
}
```

- [ ] **Step 5: Build to verify implementation compiles**

Run:

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Expected: build succeeds with `0 Error(s)`.

---

### Task 3: Verification And Scope Checks

**Files:**
- No code edits.

- [ ] **Step 1: Build the full solution**

Run:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

Expected: build succeeds with `0 Error(s)`.

- [ ] **Step 2: Refresh Godot C# global classes**

Run:

```bash
godot-mono --headless --path . --build-solutions --quit
```

Expected: exit code `0`; no `SCRIPT ERROR`, `Parse Error`, `Failed to load script`, or C# build failures.

- [ ] **Step 3: Smoke-test affected scenes**

Run:

```bash
godot-mono --headless --path . --scene res://scenes/inventory/AttributeSummaryUI.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/monster_scenes/monster.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5
```

Expected: each command exits `0`; existing unrelated UID warnings are acceptable only if they do not involve files changed by this fix.

- [ ] **Step 4: Confirm no old regression-prone names returned**

Run:

```bash
rg -n -P "^MaxHealth =|AttributeType\.(PhysPenetration|MagicPenetration)(?!Rate)|\bPhysDamageBoost\b|\bMagicDamageBoost\b|\bPhysPenetrationValue\b|\bMagicPenetrationValue\b" core entities resources scenes tests
```

Expected: no matches.

- [ ] **Step 5: Check whitespace and impacted flows**

Run:

```bash
git diff --check
```

Expected: no output.

Use GitNexus MCP:

```text
detect_changes(repo: "CUSGA", scope: "all")
```

Expected: affected flows are limited to attribute recalculation, vital synchronization, combat/UI tests, and expected resource/schema changes. If risk remains `critical`, document that it is expected because `AttributeComponent` is core shared behavior.

- [ ] **Step 6: Commit**

Only commit if the user explicitly asks for commits. Suggested commit:

```bash
git add entities/components/VitalComponentBase.cs entities/components/AttributeComponent.cs tests/CUSGA.Tests/Program.cs
git commit -m "fix: preserve current vitals during attribute recalculation"
```

---

## Self-Review

- Spec coverage: addresses both Brooks findings: runtime bug and missing regression test.
- Placeholder scan: no TBD or unspecified implementation steps remain.
- Type consistency: uses existing `AttributeType.MaxHealth`, `AttributeType.MaxEnergy`, `AttributeChangeReason.Initialization`, `HealthComponent`, `EnergyComponent`, and `VitalComponentBase` names.
