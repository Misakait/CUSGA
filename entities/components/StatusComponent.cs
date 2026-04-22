using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using CUSGA.core.attributes;
using CUSGA.core.combat.status;
using CUSGA.core.constants;
using CUSGA.core.combat;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class StatusComponent : Node
{
    [Signal]
    public delegate void StatusChangedEventHandler(StatusChangedEvent changeEvent);

    private readonly Dictionary<StringName, StatusEffectInstance> _statuses = [];

    private Node _globalEventBus;

    public event Action<StatusChangeContext> StatusChangedDetailed;

    public Node Parent => GetParent();

    public IReadOnlyCollection<StatusEffectInstance> ActiveStatuses => _statuses.Values;

    public override void _Ready()
    {
        _globalEventBus = GetNodeOrNull<Node>("/root/GlobalEventBus");
    }

    public bool HasStatus(StringName statusId)
    {
        return _statuses.ContainsKey(statusId);
    }

    public StatusEffectInstance GetStatusOrNull(StringName statusId)
    {
        return _statuses.TryGetValue(statusId, out var status)
            ? status
            : null;
    }

    public void AddStatus(StatusEffectInstance incoming)
    {
        if (incoming == null)
        {
            GD.PushError($"{nameof(StatusComponent)} received null status.");
            return;
        }

        if (incoming.Owner != Parent)
        {
            GD.PushError(
                $"Status '{incoming.Id}' owner mismatch. " +
                $"Expected '{Parent?.Name}', got '{incoming.Owner?.Name}'."
            );
            return;
        }

        if (incoming.Id == default)
        {
            GD.PushError($"{nameof(StatusEffectData)} has empty Id.");
            return;
        }

        if (_statuses.TryGetValue(incoming.Id, out var existing))
        {
            ApplyStackPolicy(existing, incoming);
            existing.OnReapplied(incoming);
            bool stackChanged = existing.TryIncreaseStack();

            NotifyStatusChanged(
                existing,
                stackChanged
                    ? StatusChangeReason.StackChanged
                    : StatusChangeReason.Refreshed,
                incoming.Source
            );

            return;
        }

        _statuses.Add(incoming.Id, incoming);
        incoming.OnApply();

        NotifyStatusChanged(incoming, StatusChangeReason.Applied, incoming.Source);
    }

    private static void ApplyStackPolicy(
        StatusEffectInstance existing,
        StatusEffectInstance incoming
    )
    {
        switch (existing.Policy)
        {
            case StackPolicy.ResetDuration:
                existing.ResetDurations();
                break;

            case StackPolicy.AddDuration:
                existing.AddDurationsFrom(incoming);
                break;

            case StackPolicy.AddStackOnly:
                break;

            default:
                GD.PushWarning($"Unhandled stack policy: {existing.Policy}");
                break;
        }
    }

    public bool RemoveStatus(StringName statusId)
    {
        if (!_statuses.TryGetValue(statusId, out var status))
        {
            return false;
        }

        status.OnRemove();
        _statuses.Remove(statusId);

        NotifyStatusChanged(status, StatusChangeReason.Removed, status.Source);
        return true;
    }

    public void ClearAllStatuses()
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnRemove();
            NotifyStatusChanged(status, StatusChangeReason.Cleared, status.Source);
        }

        _statuses.Clear();
    }

    /// <summary>
    /// 任意单位开始行动时，由战斗系统调用
    /// 处理GlobalTurnDuration和当前行动者自己的 OwnerTurnDuration
    /// </summary>
    public void OnTurnStarted(Node currentActor)
    {
        // bool anyChanged = false;

        foreach (var status in _statuses.Values.ToList())
        {
            bool changed = false;
            // 任意单位开始行动时 -1
            changed |= status.TickGlobalTurn(currentActor);

            if (currentActor == Parent)
            {
                // Buff 所属单位自己开始行动时 -1
                changed |= status.TickOwnerTurn();
            }

            if (!changed)
            {
                continue;
            }

            // anyChanged = true;
            ResolveExpiration(status);
        }

        // if (anyChanged)
        //     EmitLocalStatusChanged();
    }

    /// <summary>
    /// 当战斗系统判定“所有存活单位都至少行动过一次”时调用
    /// StatusComponent 自己不负责判断 round 边界
    /// </summary>
    public void OnRoundStarted()
    {
        // bool anyChanged = false;

        foreach (var status in _statuses.Values.ToList())
        {
            if (!status.TickRound())
            {
                continue;
            }

            // anyChanged = true;
            ResolveExpiration(status);
        }

        // if (anyChanged)
        //     EmitLocalStatusChanged();
    }

    private void ResolveExpiration(StatusEffectInstance status)
    {
        if (!status.IsExpired())
        {
            NotifyStatusChanged(status, StatusChangeReason.DurationTicked, status.Source);
            return;
        }

        if (status.TryRemoveStack())
        {
            status.ResetDurations();
            NotifyStatusChanged(status, StatusChangeReason.StackExpired, status.Source);
            return;
        }

        RemoveStatus(status.Id);
    }

    /// <summary>
    /// 发生在属性真正提交之前。
    /// 用于取消变化，修改变化，限制变化，转化变化
    /// </summary>
    public void ProcessBeforeAttributeChange(AttributeChangeContext context)
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnBeforeAttributeChange(context);

            if (context.IsCancelled)
            {
                break;
            }
        }
    }

    /// <summary>
    /// 发生在属性真正提交之后。
    /// 属性变化后触发额外效果(例如：法强提高时，抽一张牌)
    /// </summary>
    public void ProcessAfterAttributeChanged(AttributeChangeContext context)
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnAfterAttributeChanged(context);
        }
    }

    public void ProcessModifyOutgoingDamage(
        DamagePayload payload,
        ref float damage
    )
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnModifyOutgoingDamage(payload, ref damage);

            if (damage <= 0f)
            {
                damage = 0f;
                return;
            }
        }
    }

    public void ProcessModifyIncomingDamageBeforeMitigation(
        DamagePayload payload,
        ref float damage
    )
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnModifyIncomingDamageBeforeMitigation(payload, ref damage);

            if (damage <= 0f)
            {
                damage = 0f;
                return;
            }
        }
    }

    public void ProcessModifyIncomingDamageAfterMitigation(
        DamagePayload payload,
        ref float damage
    )
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnModifyIncomingDamageAfterMitigation(payload, ref damage);

            if (damage <= 0f)
            {
                damage = 0f;
                return;
            }
        }
    }

    public void ProcessBeforeHealthDamage(
        DamagePayload payload,
        ref float damage
    )
    {
        foreach (var status in _statuses.Values.ToList())
        {
            status.OnBeforeHealthDamage(payload, ref damage);

            if (damage <= 0f)
            {
                damage = 0f;
                return;
            }
        }
    }

    private void NotifyStatusChanged(
        StatusEffectInstance status,
        StatusChangeReason reason,
        Node source
    )
    {
        var context = new StatusChangeContext(
            Parent,
            source,
            status,
            reason
        );

        StatusChangedDetailed?.Invoke(context);
        var changeEvent = new StatusChangedEvent(context);

        EmitSignal(
            SignalName.StatusChanged,
            changeEvent
        );
        // EmitLocalStatusChanged();
    }

    // private void EmitLocalStatusChanged()
    // {
    //     EmitSignal(SignalName.StatusChanged, Parent);

    //     if (_globalEventBus != null)
    //         _globalEventBus.EmitSignal(GDSignals.OnStatusChanged, Parent);
    // }
}
