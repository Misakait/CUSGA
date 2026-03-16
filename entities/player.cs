using Godot;
using System;
using CUSGA.core.constants;
using CUSGA.entities.components;
namespace CUSGA.entities;

public partial class Player : CharacterBody2D
{

    private HealthComponent _health;
    private SatietyComponent _satiety;
    private EnergyComponent _energy;

    public override void _Ready()
    {
        _health = GetNode<HealthComponent>("HealthComponent");
        _satiety = GetNode<SatietyComponent>("SatietyComponent");
        _energy = GetNode<EnergyComponent>("EnergyComponent");


        _satiety.Depleted += OnSatietyDepleted;
        _health.Depleted += OnPlayerDied;
    }

    private void OnSatietyDepleted()
    {
        GD.Print("主角：我太饿了！开始掉血！");

        _health.TakeDamage(5, ElementType.None);
    }

    private void OnPlayerDied()
    {
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
    }
}
