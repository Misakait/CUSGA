using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using CUSGA.core.attributes;
using CUSGA.core.combat.status;
using CUSGA.resources.stats;

using GameAttribute = CUSGA.core.attributes.Attribute;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class AttributeComponent : Node
{
    [Signal]
    public delegate void AttributeChangedEventHandler(AttributeChangedEvent changeEvent);

    [Signal]
    public delegate void AvailablePointsChangedEventHandler(int availablePoints);

    [Export] public StartingStats InitialData;

    public int AvailablePoints { get; private set; }

    private readonly Dictionary<AttributeType, GameAttribute> _attributes = [];

    // 已提交的最终属性值：
    // RawValue + BuffModifier + Clamp + BeforeInterception 后的结果。
    private readonly Dictionary<AttributeType, float> _effectiveCache = [];

    private StatusComponent _statusComponent;

    private const int MaxRecalculateRequestsPerFlush = 64;

    private readonly Queue<RecalculateRequest> _recalculateQueue = [];
    private bool _isFlushingRecalculateQueue;

    public Node Host => GetParent();

    // public float Speed => GetEffectiveValue(AttributeType.Speed);
    // public float MagPower => GetEffectiveValue(AttributeType.MagPower);
    // public float MagResist => GetEffectiveValue(AttributeType.MagResist);
    // public float PhysAtk => GetEffectiveValue(AttributeType.PhysAtk);
    // public float PhysDef => GetEffectiveValue(AttributeType.PhysDef);
    // public float PhysDamageBoost => GetEffectiveValue(AttributeType.PhysDamageBoost);
    // public float MagicDamageBoost => GetEffectiveValue(AttributeType.MagicDamageBoost);
    [ExportGroup("Realtime Attributes (Debug)")]
    [Export]
    public float Speed
    {
        get => GetEffectiveValue(AttributeType.Speed);
        set { }
    }

    [Export]
    public float MagPower
    {
        get => GetEffectiveValue(AttributeType.MagPower);
        set { }
    }

    [Export]
    public float MagResist
    {
        get => GetEffectiveValue(AttributeType.MagResist);
        set { }
    }

    [Export]
    public float PhysAtk
    {
        get => GetEffectiveValue(AttributeType.PhysAtk);
        set { }
    }

    [Export]
    public float PhysDef
    {
        get => GetEffectiveValue(AttributeType.PhysDef);
        set { }
    }

    [Export]
    public float PhysDamageBoost
    {
        get => GetEffectiveValue(AttributeType.PhysDamageBoost);
        set { }
    }

    [Export]
    public float MagicDamageBoost
    {
        get => GetEffectiveValue(AttributeType.MagicDamageBoost);
        set { }
    }

    public override void _ValidateProperty(Godot.Collections.Dictionary property)
    {
        string propName = property["name"].AsString();

        if (propName == nameof(Speed) ||
            propName == nameof(MagPower) ||
            propName == nameof(MagResist) ||
            propName == nameof(PhysAtk) ||
            propName == nameof(PhysDef) ||
            propName == nameof(PhysDamageBoost) ||
            propName == nameof(MagicDamageBoost))
        {
            var usage = (PropertyUsageFlags)property["usage"].AsInt64();
            usage |= PropertyUsageFlags.ReadOnly;
            property["usage"] = (long)usage;
        }
    }

    public override void _Ready()
    {
        _statusComponent = Host?.GetNodeOrNull<StatusComponent>("StatusComponent");

        if (_statusComponent != null)
        {
            _statusComponent.StatusChangedDetailed += HandleStatusChanged;
        }

        if (InitialData != null)
        {
            InitializeWithData(InitialData);
        }
    }

    public override void _ExitTree()
    {
        if (_statusComponent != null)
        {
            _statusComponent.StatusChangedDetailed -= HandleStatusChanged;
        }
    }

    public void InitializeWithData(StartingStats data)
    {
        if (data == null)
        {
            GD.PushError($"{nameof(AttributeComponent)} initialized with null StartingStats.");
            return;
        }

        InitialData = data;

        _attributes.Clear();
        _effectiveCache.Clear();
        _recalculateQueue.Clear();

        SetAttribute(AttributeType.PhysAtk, "物理攻击", data.BasePhysAtk, data.PhysAtkGrowth);
        SetAttribute(AttributeType.PhysDef, "物理抗性", data.BasePhysDef, data.PhysDefGrowth);
        SetAttribute(AttributeType.MagPower, "法术强度", data.BaseMagPower, data.MagPowerGrowth);
        SetAttribute(AttributeType.MagResist, "法术抗性", data.BaseMagResist, data.MagResistGrowth);
        SetAttribute(AttributeType.Speed, "速度", data.BaseSpeed, data.SpeedGrowth);
        SetAttribute(AttributeType.PhysDamageBoost, "物理增伤", 0f, 0f);
        SetAttribute(AttributeType.MagicDamageBoost, "魔法增伤", 0f, 0f);

        GD.Print("InitializeWithData", data);

        RecalculateAllDirect(
            source: Host,
            reason: AttributeChangeReason.Initialization,
            allowInterception: false,
            emitEvents: false
        );
    }

    private void SetAttribute(
        AttributeType type,
        string displayName,
        float baseValue,
        float growth
    )
    {
        _attributes[type] = new GameAttribute(
            type,
            displayName,
            baseValue,
            growth
        );
    }

    public IReadOnlyAttribute GetAttribute(AttributeType type)
    {
        return _attributes.TryGetValue(type, out var attribute)
            ? attribute
            : null;
    }

    public IEnumerable<IReadOnlyAttribute> GetAllAttributes()
    {
        foreach (var attribute in _attributes.Values)
        {
            yield return attribute;
        }
    }

    public float GetRawValue(AttributeType type)
    {
        return _attributes.TryGetValue(type, out var attribute)
            ? attribute.RawValue
            : 0f;
    }

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

    public void EarnPoints(int amount)
    {
        if (amount <= 0)
        {
            GD.PushWarning("Cannot earn non-positive attribute points.");
            return;
        }

        AvailablePoints += amount;
        NotifyAvailablePointsChanged();
    }

    public bool TryAllocatePoint(AttributeType targetAttributeType, int amount)
    {
        if (amount <= 0)
        {
            GD.PushWarning("Cannot allocate non-positive attribute points.");
            return false;
        }

        if (AvailablePoints < amount)
        {
            GD.Print("没有足够的技能点！");
            return false;
        }

        if (!_attributes.ContainsKey(targetAttributeType))
        {
            GD.PushWarning($"Attribute {targetAttributeType} does not exist on {Host?.Name}.");
            return false;
        }

        AvailablePoints -= amount;
        NotifyAvailablePointsChanged();

        RequestRecalculateAttribute(
            type: targetAttributeType,
            source: Host,
            reason: AttributeChangeReason.AllocatedPointChanged,
            mutation: () =>
            {
                _attributes[targetAttributeType].AddPoint(amount);
            }
        );

        return true;
    }

    public bool AddPermanentBonus(
        AttributeType type,
        float amount,
        Node source = null
    )
    {
        if (!_attributes.ContainsKey(type))
        {
            GD.PushWarning($"Attribute {type} does not exist on {Host?.Name}.");
            return false;
        }

        if (Mathf.IsZeroApprox(amount))
        {
            return false;
        }

        RequestRecalculateAttribute(
            type: type,
            source: source ?? Host,
            reason: AttributeChangeReason.PermanentBonusChanged,
            mutation: () =>
            {
                _attributes[type].AddBonus(amount);
            }
        );

        return true;
    }

    public bool RemovePermanentBonus(
        AttributeType type,
        float amount,
        Node source = null
    )
    {
        if (!_attributes.ContainsKey(type))
        {
            GD.PushWarning($"Attribute {type} does not exist on {Host?.Name}.");
            return false;
        }

        if (Mathf.IsZeroApprox(amount))
        {
            return false;
        }

        RequestRecalculateAttribute(
            type: type,
            source: source ?? Host,
            reason: AttributeChangeReason.PermanentBonusChanged,
            mutation: () =>
            {
                _attributes[type].RemoveBonus(amount);
            }
        );

        return true;
    }

    public void ForceRecalculateAll(Node source = null)
    {
        RequestRecalculateAll(
            source: source ?? Host,
            reason: AttributeChangeReason.ForcedRecalculation
        );
    }

    /// <summary>
    /// Buff 添加、移除、叠层、持续时间变化时触发。
    /// Buff 可能影响任意属性，所以这里重算全部属性。
    /// </summary>
    private void HandleStatusChanged(StatusChangeContext context)
    {
        RequestRecalculateAll(
            source: context.Source ?? context.Owner,
            reason: AttributeChangeReason.StatusChanged
        );
    }

    private void RequestRecalculateAttribute(
        AttributeType type,
        Node source,
        AttributeChangeReason reason,
        Action mutation = null,
        bool allowInterception = true,
        bool emitEvents = true
    )
    {
        EnqueueRecalculate(
            RecalculateRequest.Single(
                type: type,
                source: source ?? Host,
                reason: reason,
                mutation: mutation,
                allowInterception: allowInterception,
                emitEvents: emitEvents
            )
        );
    }

    private void RequestRecalculateAll(
        Node source,
        AttributeChangeReason reason,
        Action mutation = null,
        bool allowInterception = true,
        bool emitEvents = true
    )
    {
        EnqueueRecalculate(
            RecalculateRequest.All(
                source: source ?? Host,
                reason: reason,
                mutation: mutation,
                allowInterception: allowInterception,
                emitEvents: emitEvents
            )
        );
    }

    private void EnqueueRecalculate(RecalculateRequest request)
    {
        _recalculateQueue.Enqueue(request);

        if (_isFlushingRecalculateQueue)
        {
            return;
        }

        FlushRecalculateQueue();
    }

    private void FlushRecalculateQueue()
    {
        _isFlushingRecalculateQueue = true;

        try
        {
            int processedCount = 0;

            while (_recalculateQueue.Count > 0)
            {
                if (++processedCount > MaxRecalculateRequestsPerFlush)
                {
                    _recalculateQueue.Clear();

                    GD.PushError(
                        $"{nameof(AttributeComponent)} detected a possible infinite attribute recalculation loop on {Host?.Name}."
                    );

                    return;
                }

                var request = _recalculateQueue.Dequeue();
                ProcessRecalculateRequest(request);
            }
        }
        finally
        {
            _isFlushingRecalculateQueue = false;
        }
    }

    private void ProcessRecalculateRequest(RecalculateRequest request)
    {
        request.ApplyMutation();

        if (request.Scope == AttributeRecalculateScope.AllAttributes)
        {
            foreach (var type in _attributes.Keys.ToList())
            {
                RecalculateEffectiveAttribute(
                    type: type,
                    source: request.Source,
                    reason: request.Reason,
                    allowInterception: request.AllowInterception,
                    emitEvents: request.EmitEvents
                );
            }

            return;
        }

        RecalculateEffectiveAttribute(
            type: request.Type,
            source: request.Source,
            reason: request.Reason,
            allowInterception: request.AllowInterception,
            emitEvents: request.EmitEvents
        );
    }

    private void RecalculateAllDirect(
        Node source,
        AttributeChangeReason reason,
        bool allowInterception,
        bool emitEvents
    )
    {
        foreach (var type in _attributes.Keys.ToList())
        {
            RecalculateEffectiveAttribute(
                type: type,
                source: source,
                reason: reason,
                allowInterception: allowInterception,
                emitEvents: emitEvents
            );
        }
    }

    private void RecalculateEffectiveAttribute(
        AttributeType type,
        Node source,
        AttributeChangeReason reason,
        bool allowInterception,
        bool emitEvents
    )
    {
        if (!_attributes.ContainsKey(type))
        {
            return;
        }

        float oldValue = _effectiveCache.TryGetValue(type, out var cached)
            ? cached
            : ClampAttributeValue(type, CalculateUnclampedEffectiveValue(type));

        float attemptedValue = ClampAttributeValue(
            type,
            CalculateUnclampedEffectiveValue(type)
        );

        var context = new AttributeChangeContext(
            owner: Host,
            source: source ?? Host,
            type: type,
            reason: reason,
            oldValue: oldValue,
            newValue: attemptedValue
        );

        if (allowInterception)
        {
            _statusComponent?.ProcessBeforeAttributeChange(context);
        }

        if (context.IsCancelled)
        {
            // 被拦截取消，最终值保持 oldValue
            _effectiveCache[type] = oldValue;
            return;
        }

        float finalValue = ClampAttributeValue(type, context.NewValue);

        if (float.IsNaN(finalValue) || float.IsInfinity(finalValue))
        {
            GD.PushError(
                $"Invalid attribute value calculated for {type} on {Host?.Name}: {finalValue}"
            );
            return;
        }

        if (Mathf.IsEqualApprox(oldValue, finalValue))
        {
            // cache 原本不存在，需要补 cache。
            // BeforeAttributeChange 把降低量抵消成 0。
            // 浮点近似相等。
            //
            // 不发事件，不触发 After
            _effectiveCache[type] = finalValue;
            return;
        }

        context.NewValue = finalValue;
        _effectiveCache[type] = finalValue;

        if (!emitEvents)
        {
            return;
        }

        NotifyAttributeChanged(context);

        // After 触发的新属性变化会进入队列
        _statusComponent?.ProcessAfterAttributeChanged(context);
    }

    private float CalculateUnclampedEffectiveValue(AttributeType type)
    {
        if (!_attributes.TryGetValue(type, out var attribute))
        {
            return 0f;
        }

        float baseValue = attribute.RawValue;

        float flatAdd = 0f;
        float percentAdd = 0f;
        float percentMul = 1f;

        if (_statusComponent != null)
        {
            foreach (var status in _statusComponent.ActiveStatuses)
            {
                foreach (var modifier in status.GetAttributeModifiers())
                {
                    if (modifier.Type != type)
                    {
                        continue;
                    }

                    switch (modifier.Mode)
                    {
                        case AttributeModifierMode.FlatAdd:
                            flatAdd += modifier.ValuePerStack * modifier.Stacks;
                            break;

                        case AttributeModifierMode.PercentAdd:
                            percentAdd += modifier.ValuePerStack * modifier.Stacks;
                            break;

                        case AttributeModifierMode.PercentMul:
                            percentMul *= Mathf.Pow(1f + modifier.ValuePerStack, modifier.Stacks);
                            break;

                        default:
                            GD.PushWarning($"Unhandled attribute modifier mode: {modifier.Mode}");
                            break;
                    }
                }
            }
        }

        return (baseValue + flatAdd) * (1f + percentAdd) * percentMul;
    }

    private static float ClampAttributeValue(AttributeType type, float value)
    {
        return type switch
        {
            AttributeType.Speed => Mathf.Max(1f, value),

            AttributeType.PhysAtk or
            AttributeType.PhysDef or
            AttributeType.MagPower or
            AttributeType.MagResist => Mathf.Max(0f, value),
            AttributeType.PhysDamageBoost or
            AttributeType.MagicDamageBoost => Mathf.Max(-1f, value),

            _ => value
        };
    }

    private void NotifyAvailablePointsChanged()
    {
        EmitSignal(SignalName.AvailablePointsChanged, AvailablePoints);
    }

    private void NotifyAttributeChanged(AttributeChangeContext context)
    {
        var changeEvent = new AttributeChangedEvent(context);

        EmitSignal(
            SignalName.AttributeChanged,
            changeEvent
        );
    }
}
