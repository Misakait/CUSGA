using Godot;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;
using System;

namespace CUSGA.entities;

[GlobalClass]
public partial class Monster : Node2D
{
    [Export]
    public MonsterData BaseData { get; set; }

    public HealthComponent Health { get; private set; }
    public AttributeComponent Attributes { get; private set; }
    public FactionComponent Faction { get; private set; }
    public StatusComponent Status { get; private set; }
    private LootComponent Loot { get; set; }

    private ProgressBar _healthBar;
    private Label _healthText;

    public override void _Ready()
    {
        Attributes = GetNode<AttributeComponent>("Components/AttributeComponent");
        Faction = GetNode<FactionComponent>("Components/FactionComponent");
        Health = GetNode<HealthComponent>("Components/HealthComponent");
        Status = GetNode<StatusComponent>("%StatusComponent");
        Loot = GetNodeOrNull<LootComponent>("Components/LootComponent");
        Health.Depleted += HandleDeath;
        Health.ValueChanged += OnHealthChanged;

        _healthBar = GetNode<ProgressBar>("HealthBar");
        if (_healthBar != null)
        {
            _healthText = _healthBar.GetNodeOrNull<Label>("HealthText");
        }

        if (BaseData != null)
        {
            Initialize(BaseData);
        }
    }

    private void OnHealthChanged(int currentValue, int maxValue)
    {
        if (_healthBar == null) throw new System.NullReferenceException("HealthBar node is missing on Monster!");
        if (_healthText == null) throw new System.NullReferenceException("HealthText node is missing on Monster!");

        _healthBar.MaxValue = maxValue;
        _healthBar.Value = currentValue;
        _healthText.Text = $"{currentValue}/{maxValue}";
    }

    private void HandleDeath()
    {
        Loot?.TriggerDrop(GlobalPosition, 0);
        QueueFree();
    }

    public override void _ExitTree()
    {
        Health.Depleted -= HandleDeath;
        Health.ValueChanged -= OnHealthChanged;
    }
    public void Initialize(MonsterData data)
    {
        BaseData = data;
        Attributes.InitializeWithData(data.InitialAttributes);
        Faction.Faction = data.Faction;
        Health.InitializeMax(data.MaxHealth);

        // 实例化图纸里配置的美术预制体
        // if (data.ModelScene != null)
        // {
        //     var visualModel = data.ModelScene.Instantiate();
        //     _modelContainer.AddChild(visualModel);
        // }

        // 初始化行为树
        // var behaviorTree = data.BehaviorTreeScene.Instantiate();
        // if (behaviorTree != null)
        // {
        //     BehaviorTree.AddChild(behaviorTree);
        // }
    }
}
