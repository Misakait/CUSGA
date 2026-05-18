using Godot;
using Godot.Collections;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;
using CUSGA.resources.item.card;
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
    private Area2D _area2D;

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

        _area2D = GetNode<Area2D>("Area2D");
        if (_area2D != null)
        {
            _area2D.MouseEntered += OnMouseEntered;
            _area2D.MouseExited += OnMouseExited;
        }

        if (BaseData != null)
        {
            Initialize(BaseData);
        }
    }

    private void OnMouseEntered()
    {
        var tooltipPanels = GetTree().GetNodesInGroup("tooltip_panel");
        if (tooltipPanels.Count > 0)
        {
            var panel = tooltipPanels[0];
            string name = BaseData != null ? BaseData.MonsterName : "未知怪物";
            panel.Call("show_tooltip", name, "敌人");
        }
    }

    private void OnMouseExited()
    {
        var tooltipPanels = GetTree().GetNodesInGroup("tooltip_panel");
        if (tooltipPanels.Count > 0)
        {
            var panel = tooltipPanels[0];
            panel.Call("hide_tooltip");
        }
    }

    private void OnHealthChanged(int currentValue, int maxValue)
    {
        if (_healthBar == null)
        {
            throw new System.NullReferenceException("HealthBar node is missing on Monster!");
        }

        _healthBar.Call("update_stat", currentValue, maxValue, false);
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

        if (_area2D != null)
        {
            _area2D.MouseEntered -= OnMouseEntered;
            _area2D.MouseExited -= OnMouseExited;
        }
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

    // 获取怪物的技能卡池（直接复用玩家技能卡资源）
    public Array<SkillCardData> GetSkillCards()
    {
        return BaseData?.SkillCards ?? [];
    }

    // 从技能卡池中随机选取一张，用于怪物回合自动施放
    public SkillCardData GetRandomSkillCard()
    {
        var cards = GetSkillCards();
        if (cards == null || cards.Count == 0)
        {
            return null;
        }

        var index = (int)(GD.Randi() % (uint)cards.Count);
        return cards[index];
    }
}
