using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using CUSGA.core.attributes;
using CUSGA.core.combat.status;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;

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

    /// <summary>
    /// 获取当前激活状态的快照，供 GDScript UI 安全遍历。
    /// </summary>
    /// <returns>按当前字典顺序复制出的状态数组；调用方只能读取，不能通过该数组修改组件内部状态。</returns>
    public Godot.Collections.Array<StatusEffectInstance> GetActiveStatusesSnapshot()
    {
        var snapshot = new Godot.Collections.Array<StatusEffectInstance>();
        foreach (var status in _statuses.Values)
        {
            snapshot.Add(status);
        }

        return snapshot;
    }

    private long _nextAppliedSequence;

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

        // if (incoming.Owner != Parent)
        // {
        //     GD.PushError(
        //         $"Status '{incoming.Id}' owner mismatch. " +
        //         $"Expected '{Parent?.Name}', got '{incoming.Owner?.Name}'."
        //     );
        //     return;
        // }

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
            GD.Print("ReapplyStatus", incoming.Id, "stackChanged", stackChanged);
            NotifyStatusChanged(
                existing,
                stackChanged
                    ? StatusChangeReason.StackChanged
                    : StatusChangeReason.Refreshed,
                incoming.Source
            );

            return;
        }

        incoming.AppliedSequence = _nextAppliedSequence++;
        _statuses.Add(incoming.Id, incoming);
        incoming.OnApply();
        GD.Print("Owner:", Parent.GetParent().Name, ", AddStatus: ", incoming.Id);
        NotifyStatusChanged(incoming, StatusChangeReason.Applied, incoming.Source);
    }
    private List<StatusEffectInstance> GetStatusesForHook(StatusHookPhase phase)
    {
        return GetStatusesForHook(phase, _statuses.Values);
    }

    private static List<StatusEffectInstance> GetStatusesForHook(
        StatusHookPhase phase,
        IEnumerable<StatusEffectInstance> statuses
    )
    {
        return [.. statuses
            .OrderBy(status => status.GetHookPriority(phase))
            .ThenBy(status => status.AppliedSequence)
            .ThenBy(status => status.Id.ToString())];
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
        GD.Print("RemoveStatus", statusId);
        status.OnRemove();
        _statuses.Remove(statusId);

        NotifyStatusChanged(status, StatusChangeReason.Removed, status.Source);
        return true;
    }

    public void ClearAllStatuses()
    {
        foreach (var id in _statuses.Keys.ToList())
        {
            RemoveStatus(id);
            // status.OnRemove();
            // NotifyStatusChanged(status, StatusChangeReason.Cleared, status.Source);
        }

        _statuses.Clear();
    }

    /// <summary>
    /// 任意单位开始行动时，由战斗系统调用。
    /// 触发回合开始 hook，并按配置在开始阶段扣减持续时间。
    /// </summary>
    public void OnTurnStarted(Node currentActor)
    {
        ProcessTurnPhase(
            currentActor,
            DurationTickTiming.Start,
            StatusHookPhase.GlobalTurnStart,
            status => status.OnGlobalTurnStart(currentActor),
            StatusHookPhase.OwnerTurnStart,
            status => status.OnOwnerTurnStart()
        );
    }

    /// <summary>
    /// 任意单位结束行动时，由战斗系统调用。
    /// 触发回合结束 hook，并按配置在结束阶段扣减持续时间。
    /// </summary>
    public void OnTurnEnded(Node currentActor)
    {
        ProcessTurnPhase(
            currentActor,
            DurationTickTiming.End,
            StatusHookPhase.GlobalTurnEnd,
            status => status.OnGlobalTurnEnd(currentActor),
            StatusHookPhase.OwnerTurnEnd,
            status => status.OnOwnerTurnEnd()
        );
    }

    /// <summary>
    /// 当战斗系统判定“所有存活单位都至少行动过一次”时调用。
    /// StatusComponent 自己不负责判断 round 边界。
    /// </summary>
    public void OnRoundStarted()
    {
        GD.Print("OnRoundStarted");
        ProcessRoundPhase(
            DurationTickTiming.Start,
            StatusHookPhase.RoundStart,
            status => status.OnRoundStart()
        );
    }

    /// <summary>
    /// 当战斗系统判定一轮结束时调用。
    /// StatusComponent 自己不负责判断 round 边界。
    /// </summary>
    public void OnRoundEnded()
    {
        GD.Print("OnRoundEnded");
        ProcessRoundPhase(
            DurationTickTiming.End,
            StatusHookPhase.RoundEnd,
            status => status.OnRoundEnd()
        );
    }

    private void ProcessTurnPhase(
        Node currentActor,
        DurationTickTiming timing,
        StatusHookPhase globalHookPhase,
        Action<StatusEffectInstance> invokeGlobalHook,
        StatusHookPhase ownerHookPhase,
        Action<StatusEffectInstance> invokeOwnerHook
    )
    {
        var statuses = _statuses.Values.ToList();

        foreach (var status in GetStatusesForHook(globalHookPhase, statuses))
        {
            if (!IsActiveStatus(status))
            {
                continue;
            }

            invokeGlobalHook(status);
        }

        foreach (var status in GetStatusesForHook(ownerHookPhase, statuses))
        {
            if (!IsActiveStatus(status) || !IsStatusOwnerTurn(status, currentActor))
            {
                continue;
            }

            invokeOwnerHook(status);
        }

        TickTurnDurations(statuses, currentActor, timing);
    }

    private void ProcessRoundPhase(
        DurationTickTiming timing,
        StatusHookPhase hookPhase,
        Action<StatusEffectInstance> invokeHook
    )
    {
        var statuses = _statuses.Values.ToList();

        foreach (var status in GetStatusesForHook(hookPhase, statuses))
        {
            if (!IsActiveStatus(status))
            {
                continue;
            }

            invokeHook(status);
        }

        foreach (var status in statuses)
        {
            if (!IsActiveStatus(status) || !status.TickRoundDuration(timing))
            {
                continue;
            }

            ResolveExpiration(status);
        }
    }

    private void TickTurnDurations(
        IEnumerable<StatusEffectInstance> statuses,
        Node currentActor,
        DurationTickTiming timing
    )
    {
        foreach (var status in statuses)
        {
            if (!IsActiveStatus(status))
            {
                continue;
            }

            bool changed = status.TickGlobalTurnDuration(timing);

            if (IsStatusOwnerTurn(status, currentActor))
            {
                changed |= status.TickOwnerTurnDuration(timing);
            }

            if (!changed || !IsActiveStatus(status))
            {
                continue;
            }

            ResolveExpiration(status);
        }
    }


    private bool IsActiveStatus(StatusEffectInstance status)
    {
        return _statuses.TryGetValue(status.Id, out var activeStatus) &&
            ReferenceEquals(activeStatus, status);
    }

    private bool IsStatusOwnerTurn(StatusEffectInstance status, Node currentActor)
    {
        return currentActor == status.Owner ||
            currentActor == Parent ||
            currentActor == Parent?.GetParent();
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
        foreach (var status in GetStatusesForHook(StatusHookPhase.BeforeAttributeChange))
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
        foreach (var status in GetStatusesForHook(StatusHookPhase.AfterAttributeChanged))
        {
            status.OnAfterAttributeChanged(context);
        }
    }

    /// <summary>
    /// 在整张技能开始执行前通知所有状态。
    /// </summary>
    /// <param name="context">本次技能执行修正上下文。</param>
    public void ProcessBeforeSkillExecution(SkillExecutionModifierContext context)
    {
        var statuses = _statuses.Values.ToList();

        foreach (var status in GetStatusesForHook(StatusHookPhase.BeforeSkillExecution, statuses))
        {
            if (!IsActiveStatus(status))
            {
                continue;
            }

            status.OnBeforeSkillExecution(context);
        }
    }

    /// <summary>
    /// 在整张技能全部效果执行后通知所有状态，并统一扣减被标记的限次状态。
    /// </summary>
    /// <param name="context">本次技能执行修正上下文。</param>
    public void ProcessAfterSkillExecution(SkillExecutionModifierContext context)
    {
        var statuses = _statuses.Values.ToList();

        foreach (var status in GetStatusesForHook(StatusHookPhase.AfterSkillExecution, statuses))
        {
            if (!IsActiveStatus(status))
            {
                continue;
            }

            status.OnAfterSkillExecution(context);
        }

        ConsumeMarkedSkillExecutionStatuses(context);
    }

    /// <summary>
    /// 在伤害效果进入段数循环前应用施法者状态的段数修正。
    /// </summary>
    /// <param name="context">伤害段数修正上下文。</param>
    /// <param name="hitCount">当前有效段数候选值。</param>
    public void ProcessModifyDamageHitCount(
        DamageEffectHitCountContext context,
        ref int hitCount
    )
    {
        foreach (var status in GetStatusesForHook(StatusHookPhase.ModifyDamageHitCount))
        {
            status.OnModifyDamageHitCount(context, ref hitCount);
            if (hitCount <= 0)
            {
                hitCount = 0;
                return;
            }
        }
    }

    /// <summary>
    /// 在单段伤害创建伤害载荷前应用施法者状态的基础伤害修正。
    /// </summary>
    /// <param name="context">单段伤害修正上下文。</param>
    /// <param name="damage">当前本段基础伤害候选值。</param>
    public void ProcessModifyDamageEffectSegmentDamage(
        DamageEffectSegmentContext context,
        ref int damage
    )
    {
        foreach (var status in GetStatusesForHook(StatusHookPhase.ModifyDamageEffectSegmentDamage))
        {
            status.OnModifyDamageEffectSegmentDamage(context, ref damage);
            if (damage <= 0)
            {
                damage = 0;
                return;
            }
        }
    }

    public void ProcessModifyOutgoingDamage(
        DamagePayload payload,
        ref float damage
    )
    {
        foreach (var status in GetStatusesForHook(StatusHookPhase.ModifyOutgoingDamage))
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
        foreach (var status in GetStatusesForHook(StatusHookPhase.ModifyIncomingDamageBeforeMitigation))
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
        foreach (var status in GetStatusesForHook(StatusHookPhase.ModifyIncomingDamageAfterMitigation))
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
        foreach (var status in GetStatusesForHook(StatusHookPhase.BeforeHealthDamage))
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

    private void ConsumeMarkedSkillExecutionStatuses(SkillExecutionModifierContext context)
    {
        foreach (var statusId in context.StatusIdsMarkedForConsumption.ToList())
        {
            if (!_statuses.TryGetValue(statusId, out var status))
            {
                continue;
            }

            if (status.ConsumeMarkedSkillExecutionUse())
            {
                RemoveStatus(statusId);
                continue;
            }

            NotifyStatusChanged(status, StatusChangeReason.Refreshed, status.Source);
        }
    }

    // private void EmitLocalStatusChanged()
    // {
    //     EmitSignal(SignalName.StatusChanged, Parent);

    //     if (_globalEventBus != null)
    //         _globalEventBus.EmitSignal(GDSignals.OnStatusChanged, Parent);
    // }
}
