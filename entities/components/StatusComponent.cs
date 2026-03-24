using CUSGA.core.combat;
using CUSGA.core.constants;
using Godot;
using System.Collections.Generic;
using System.Linq;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class StatusComponent : Node
{
    private readonly Dictionary<StringName, StatusEffect> _buffList = [];
    private Node _globalEventBus;
    public IEnumerable<StatusEffect> ActiveStatuses => _buffList.Values;

    public override void _Ready()
    {
        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
    }

    public void AddStatus(StatusEffect buff)
    {
        buff.Owner = GetParent();

        if (_buffList.TryGetValue(buff.Id, out StatusEffect existing))
        {
            switch (existing.Policy)
            {
                case StackPolicy.ResetDuration:
                    existing.RoundDuration = buff.InitRoundDuration;
                    existing.PhaseDuration = buff.InitPhaseDuration;
                    break;
                case StackPolicy.AddDuration:
                    existing.RoundDuration += buff.InitRoundDuration;
                    existing.PhaseDuration += buff.InitPhaseDuration;
                    break;
            }

            if (existing.CurrentStacks < existing.MaxStacks)
            {
                existing.CurrentStacks++;
                existing.OnStackIncreased(existing.CurrentStacks);
            }
        }
        else
        {
            _buffList[buff.Id] = buff;
            buff.OnApply();
        }

        _globalEventBus.EmitSignal(GDSignals.OnStatusChanged, buff.Owner);
    }

    public void RemoveStatus(StringName buffId)
    {
        if (_buffList.TryGetValue(buffId, out StatusEffect buff))
        {
            buff.OnRemove();
            _buffList.Remove(buffId);

            _globalEventBus.EmitSignal(GDSignals.OnStatusChanged, buff.Owner);
        }
    }

    public void OnRoundStart()
    {
        ProcessTimeTick(isRoundTick: true);
    }

    public void OnPhaseStart(Node currentActor)
    {

        bool isMyTurn = (currentActor == GetParent());

        ProcessTimeTick(isRoundTick: false, isMyTurn: isMyTurn);
    }


    private void ProcessTimeTick(bool isRoundTick, bool isMyTurn = false)
    {
        List<StringName> toRemove = [];

        foreach (var buff in _buffList.Values.ToList())
        {
            bool timeDecreased = false;

            // 处理大轮次
            if (isRoundTick && buff.InitRoundDuration > 0)
            {
                buff.OnRoundStart();
                buff.RoundDuration--;
                timeDecreased = true;
            }

            // 处理小回合
            if (!isRoundTick && buff.InitPhaseDuration > 0)
            {
                if (buff.IsAllPhase || isMyTurn)
                {
                    buff.OnPhaseStart();
                    buff.PhaseDuration--;
                    timeDecreased = true;
                }
            }

            // 如果时间流失了，检查是否过期并执行逐层掉落
            if (timeDecreased && buff.RoundDuration <= 0 && buff.PhaseDuration <= 0)
            {
                if (buff.CurrentStacks > 1)
                {
                    buff.CurrentStacks--;
                    buff.OnStackRemoved(buff.CurrentStacks);
                    // 掉层后恢复初始时间
                    buff.RoundDuration = buff.InitRoundDuration;
                    buff.PhaseDuration = buff.InitPhaseDuration;
                }
                else
                {
                    toRemove.Add(buff.Id);
                }
            }
        }

        foreach (var id in toRemove) RemoveStatus(id);


        if (_buffList.Count > 0)
        {
            _globalEventBus.EmitSignal(GDSignals.OnStatusChanged, this);
        }
    }
}
