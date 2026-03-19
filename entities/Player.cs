using Godot;
using System;
using CUSGA.core.constants;
using CUSGA.entities.components;
using CUSGA.resources.talents;
using System.Collections.Generic;
namespace CUSGA.entities;

public partial class Player : CharacterBody2D
{

    private HealthComponent _health;
    private SatietyComponent _satiety;
    private EnergyComponent _energy;
    private AttributeComponent _attribute;
    public TagComponent TagComponent { get; private set; }

    private Node _globalEventBus;

    public override void _Ready()
    {
        _health = GetNode<HealthComponent>("HealthComponent");
        _satiety = GetNode<SatietyComponent>("SatietyComponent");
        _energy = GetNode<EnergyComponent>("EnergyComponent");
        _attribute = GetNode<AttributeComponent>("AttributeComponent");
        TagComponent = GetNode<TagComponent>("TagComponent");

        _satiety.Depleted += OnSatietyDepleted;
        _health.Depleted += OnPlayerDied;

        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        _globalEventBus.Connect("on_player_acquired_talent", Callable.From<TalentData>(AbsorbTalent));
    }

    private void AbsorbTalent(TalentData newTalent)
    {
        GD.Print($"主角感受到神秘力量涌入：{newTalent.TalentName}！");
        if (newTalent.Effects != null)
        {
            foreach (TalentEffect effect in newTalent.Effects)
            {
                effect.Apply(this);
            }
        }
    }

    private void OnSatietyDepleted()
    {
        GD.Print("主角：我太饿了！开始掉血！");

        _health.TakeDamage(5, ElementType.None);
    }

    private void OnPlayerDied()
    {
        _globalEventBus.EmitSignal("player_died");
        GD.Print("主角死亡，游戏结束！");
    }


    public override void _ExitTree()
    {
        if (_satiety != null)
        {
            _satiety.Depleted -= OnSatietyDepleted;
        }

        if (_health != null)
        {
            _health.Depleted -= OnPlayerDied;
        }

        if (_globalEventBus != null)
        {
            _globalEventBus.Disconnect("on_player_acquired_talent", Callable.From<TalentData>(AbsorbTalent));
        }
    }
}
