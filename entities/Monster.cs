using Godot;
using Godot.Collections;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;
using CUSGA.core.combat.skills;
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
    public MonsterSkillComponent SkillComponent { get; private set; }
    private LootComponent Loot { get; set; }

    private ProgressBar _healthBar;
    private Area2D _area2D;
    private Label _cardNameLabel;
    private Label _elementLabel;
    private Node _tooltipPanel;
    private Tween _visualScaleTween;
    private readonly System.Collections.Generic.Dictionary<Node, Vector2> _visualScaleBaseMap = new();
    private readonly System.Collections.Generic.Dictionary<Node, Vector2> _visualPositionBaseMap = new();

    public override void _Ready()
    {
        Attributes = GetNode<AttributeComponent>("Components/AttributeComponent");
        Faction = GetNode<FactionComponent>("Components/FactionComponent");
        Health = GetNode<HealthComponent>("Components/HealthComponent");
        Status = GetNode<StatusComponent>("%StatusComponent");
        Loot = GetNodeOrNull<LootComponent>("Components/LootComponent");
        SkillComponent = GetNodeOrNull<MonsterSkillComponent>("Components/SkillComponent");
        Health.Depleted += HandleDeath;
        Health.ValueChanged += OnHealthChanged;

        _healthBar = GetNode<ProgressBar>("HealthBar");
        _cardNameLabel = GetNodeOrNull<Label>("CardName");
        _elementLabel = GetNodeOrNull<Label>("Element");

        _area2D = GetNode<Area2D>("Area2D");
        CacheVisualScaleTargets();
        if (_area2D != null)
        {
            _area2D.MouseEntered += OnMouseEntered;
            _area2D.MouseExited += OnMouseExited;
        }

        _tooltipPanel = FindTooltipPanel();

        if (BaseData != null)
        {
            Initialize(BaseData);
        }
        else
        {
            UpdateCardUi(null);
        }
    }

    private void OnMouseEntered()
    {
        if (_tooltipPanel == null || !IsInstanceValid(_tooltipPanel))
        {
            _tooltipPanel = FindTooltipPanel();
        }

        if (_tooltipPanel == null || !IsInstanceValid(_tooltipPanel))
        {
            return;
        }

        string name = BaseData != null ? BaseData.MonsterName : "未知怪物";
        _tooltipPanel.Call("show_tooltip", name, "敌人");
    }

    private void OnMouseExited()
    {
        if (_tooltipPanel == null || !IsInstanceValid(_tooltipPanel))
        {
            _tooltipPanel = FindTooltipPanel();
        }

        if (_tooltipPanel != null && IsInstanceValid(_tooltipPanel))
        {
            _tooltipPanel.Call("hide_tooltip");
        }
    }

    private Node FindTooltipPanel()
    {
        var panels = GetTree().GetNodesInGroup("tooltip_panel");
        if (panels == null || panels.Count == 0)
        {
            return null;
        }

        Node current = this;
        while (current != null)
        {
            foreach (var panel in panels)
            {
                if (panel is Node panelNode && current.IsAncestorOf(panelNode))
                {
                    return panelNode;
                }
            }

            current = current.GetParent();
        }

        return panels[0];
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
        if (data.SkillSet != null)
        {
            SkillComponent?.Initialize(data.SkillSet);
        }
        UpdateCardUi(data);

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

    private void UpdateCardUi(MonsterData data)
    {
        if (_cardNameLabel != null)
        {
            _cardNameLabel.Text = data?.MonsterName ?? string.Empty;
        }

        if (_elementLabel != null)
        {
            _elementLabel.Text = data != null
                ? GetElementDisplayName(data.ElementalProperty)
                : string.Empty;
        }
    }

    private static string GetElementDisplayName(ElementType element)
    {
        return element switch
        {
            ElementType.Wood => "木",
            ElementType.Metal => "金",
            ElementType.Water => "水",
            ElementType.Earth => "土",
            ElementType.Fire => "火",
            _ => "无"
        };
    }

    private void CacheVisualScaleTargets()
    {
        _visualScaleBaseMap.Clear();
        _visualPositionBaseMap.Clear();
        string[] visualNodePaths = ["Sprite2D", "CardName", "Element", "MonsterAttribute", "StatusEffectBar"];

        foreach (string path in visualNodePaths)
        {
            Node node = GetNodeOrNull<Node>(path);
            if (node == null)
            {
                continue;
            }

            // 只缓存卡面和卡面内部内容的初始 scale，故意不包含 HealthBar，避免目标高亮/行动高亮时血条跟着放大。
            if (node is Node2D node2D)
            {
                _visualScaleBaseMap[node] = node2D.Scale;
                _visualPositionBaseMap[node] = node2D.Position;
            }
            else if (node is Control control)
            {
                _visualScaleBaseMap[node] = control.Scale;
                _visualPositionBaseMap[node] = control.Position;
            }
        }
    }

    /// <summary>
    /// 统一缩放怪物卡面与内部文字/属性内容，但不缩放血条。
    /// </summary>
    /// <param name="targetSpriteScale">怪物卡面 Sprite2D 的目标缩放值。</param>
    /// <param name="duration">缩放动画持续时间（秒）。</param>
    /// <returns>无返回值。</returns>
    public void TweenVisualScale(Vector2 targetSpriteScale, double duration)
    {
        if (_visualScaleBaseMap.Count == 0)
        {
            CacheVisualScaleTargets();
        }

        Node spriteNode = GetNodeOrNull<Node>("Sprite2D");
        if (spriteNode == null || !_visualScaleBaseMap.TryGetValue(spriteNode, out Vector2 baseSpriteScale))
        {
            return;
        }

        Vector2 ratio = new(
            baseSpriteScale.X != 0f ? targetSpriteScale.X / baseSpriteScale.X : 1f,
            baseSpriteScale.Y != 0f ? targetSpriteScale.Y / baseSpriteScale.Y : 1f
        );

        if (_visualScaleTween != null && _visualScaleTween.IsRunning())
        {
            _visualScaleTween.Kill();
        }

        _visualScaleTween = CreateTween().SetParallel(true);
        foreach (var pair in _visualScaleBaseMap)
        {
            Vector2 targetScale = pair.Key == spriteNode
                ? targetSpriteScale
                : new Vector2(pair.Value.X * ratio.X, pair.Value.Y * ratio.Y);
            _visualScaleTween.TweenProperty(pair.Key, "scale", targetScale, duration);

            if (_visualPositionBaseMap.TryGetValue(pair.Key, out Vector2 basePosition))
            {
                // 同步缩放位置才能接近“父节点整体缩放”的视觉效果，但 HealthBar 没被缓存，所以它的位置和大小都会保持原样。
                Vector2 targetPosition = new(basePosition.X * ratio.X, basePosition.Y * ratio.Y);
                _visualScaleTween.TweenProperty(pair.Key, "position", targetPosition, duration);
            }
        }
    }

    /// <summary>
    /// 将怪物卡面与内部内容恢复到场景中的初始缩放，血条保持不变。
    /// </summary>
    /// <param name="duration">缩放动画持续时间（秒）。</param>
    /// <returns>无返回值。</returns>
    public void ResetVisualScale(double duration)
    {
        if (_visualScaleBaseMap.Count == 0)
        {
            CacheVisualScaleTargets();
        }

        Node spriteNode = GetNodeOrNull<Node>("Sprite2D");
        if (spriteNode != null && _visualScaleBaseMap.TryGetValue(spriteNode, out Vector2 baseSpriteScale))
        {
            TweenVisualScale(baseSpriteScale, duration);
        }
    }

    /// <summary>
    /// 从技能组件获取当前怪物配置的战斗技能。
    /// </summary>
    /// <returns>当前怪物可用的有效战斗技能数组。</returns>
    public Array<CombatSkillData> GetCombatSkills()
    {
        return SkillComponent?.GetCombatSkills() ?? [];
    }

    /// <summary>
    /// 为怪物自动回合选择一个战斗技能。
    /// </summary>
    /// <returns>已配置的战斗技能；没有技能组件或没有技能时返回 null。</returns>
    public CombatSkillData GetRandomCombatSkill()
    {
        return SkillComponent?.GetRandomCombatSkill();
    }
}
