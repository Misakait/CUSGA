using Godot;
using Godot.Collections;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;
using CUSGA.core.combat.skills;
using CUSGA.resources.stats;
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
    // 目标选择呼吸动画独立保存，避免状态切换时遗留循环 Tween 持续写入卡面缩放。
    private Tween _targetSelectionPulseTween;
    // 绿色目标描边节点仅在选中状态显示，缺失时视觉接口会安全降级。
    private Line2D _targetSelectionOutline;
    // 每个卡面节点的初始缩放值用于统一应用比例缩放，血条不会写入该映射。
    private readonly System.Collections.Generic.Dictionary<Node, Vector2> _visualScaleBaseMap = new();
    // 每个卡面节点的初始调制颜色用于在取消不可选状态后精确恢复原有美术颜色。
    private readonly System.Collections.Generic.Dictionary<CanvasItem, Color> _visualModulateBaseMap = new();
    // 每个卡面节点的初始位置用于让内部文本和属性与卡面缩放保持相对布局。
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
        _targetSelectionOutline = GetNodeOrNull<Line2D>("TargetSelectionOutline");

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
        Attributes.InitializeWithData(data.InitialAttributes ?? new StartingStats());
        Faction.Faction = data.Faction;
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
        _visualModulateBaseMap.Clear();
        _visualPositionBaseMap.Clear();
        string[] visualNodePaths = ["Sprite2D", "CardName", "Element", "MonsterAttribute", "StatusEffectBar", "TargetSelectionOutline"];

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

            if (node is CanvasItem canvasItem)
            {
                _visualModulateBaseMap[canvasItem] = canvasItem.Modulate;
            }
        }
    }

    /// <summary>
    /// 将目标选择后的静态表现应用到怪物卡面，并在需要时显示绿色描边。
    /// </summary>
    /// <param name="targetSpriteScale">怪物卡面 Sprite2D 的目标缩放值。</param>
    /// <param name="isDimmed">是否将卡面变暗为不可选状态。</param>
    /// <param name="dimColor">不可选状态叠乘到原始卡面颜色的颜色倍率。</param>
    /// <param name="showOutline">是否显示目标选择描边。</param>
    /// <param name="outlineColor">目标选择描边使用的颜色。</param>
    /// <param name="outlineWidth">目标选择描边使用的像素宽度。</param>
    /// <param name="duration">缩放过渡持续时间（秒）。</param>
    /// <returns>无返回值。</returns>
    public void ApplyTargetSelectionVisual(
        Vector2 targetSpriteScale,
        bool isDimmed,
        Color dimColor,
        bool showOutline,
        Color outlineColor,
        float outlineWidth,
        double duration)
    {
        StopTargetSelectionPulse();
        SetTargetSelectionDimming(isDimmed, dimColor);
        SetTargetSelectionOutline(showOutline, outlineColor, outlineWidth);
        TweenVisualScale(targetSpriteScale, duration);
    }

    /// <summary>
    /// 启动怪物卡面的循环呼吸缩放，用于提示仍可手动选择的目标。
    /// </summary>
    /// <param name="minimumSpriteScale">呼吸动画的最小 Sprite2D 缩放值。</param>
    /// <param name="maximumSpriteScale">呼吸动画的最大 Sprite2D 缩放值。</param>
    /// <param name="halfCycleDuration">从最小值到最大值或反向的单程持续时间（秒）。</param>
    /// <returns>无返回值。</returns>
    public void StartTargetSelectionPulse(
        Vector2 minimumSpriteScale,
        Vector2 maximumSpriteScale,
        double halfCycleDuration)
    {
        StopTargetSelectionPulse();
        SetTargetSelectionDimming(false, Colors.White);
        SetTargetSelectionOutline(false, Colors.White, 0f);

        if (!TryGetBaseSpriteScale(out _))
        {
            return;
        }

        // 呼吸缩放与行动表现共用同一批卡面节点；启动前先终止静态缩放，避免两个 Tween 争夺同一属性。
        if (_visualScaleTween != null && _visualScaleTween.IsRunning())
        {
            _visualScaleTween.Kill();
        }

        _targetSelectionPulseTween = CreateTween();
        _targetSelectionPulseTween.SetParallel(true);
        AppendVisualScaleProperties(_targetSelectionPulseTween, maximumSpriteScale, halfCycleDuration);
        _targetSelectionPulseTween.Chain().SetParallel(true);
        AppendVisualScaleProperties(_targetSelectionPulseTween, minimumSpriteScale, halfCycleDuration);
        _targetSelectionPulseTween.SetLoops();
    }

    /// <summary>
    /// 停止目标选择呼吸动画，但不改变当前卡面缩放、颜色或描边状态。
    /// </summary>
    /// <returns>无返回值。</returns>
    public void StopTargetSelectionPulse()
    {
        if (_targetSelectionPulseTween != null && _targetSelectionPulseTween.IsRunning())
        {
            _targetSelectionPulseTween.Kill();
        }

        _targetSelectionPulseTween = null;
    }

    /// <summary>
    /// 将怪物卡恢复为普通目标选择状态，清除呼吸、变暗和绿色描边。
    /// </summary>
    /// <param name="normalSpriteScale">怪物卡面 Sprite2D 的正常缩放值。</param>
    /// <param name="duration">缩放还原持续时间（秒）。</param>
    /// <returns>无返回值。</returns>
    public void ResetTargetSelectionVisual(Vector2 normalSpriteScale, double duration)
    {
        StopTargetSelectionPulse();
        SetTargetSelectionDimming(false, Colors.White);
        SetTargetSelectionOutline(false, Colors.White, 0f);
        TweenVisualScale(normalSpriteScale, duration);
    }

    private void SetTargetSelectionDimming(bool isDimmed, Color dimColor)
    {
        if (_visualModulateBaseMap.Count == 0)
        {
            CacheVisualScaleTargets();
        }

        foreach (var pair in _visualModulateBaseMap)
        {
            pair.Key.Modulate = isDimmed
                ? new Color(
                    pair.Value.R * dimColor.R,
                    pair.Value.G * dimColor.G,
                    pair.Value.B * dimColor.B,
                    pair.Value.A * dimColor.A)
                : pair.Value;
        }
    }

    private void SetTargetSelectionOutline(bool isVisible, Color outlineColor, float outlineWidth)
    {
        if (_targetSelectionOutline == null || !IsInstanceValid(_targetSelectionOutline))
        {
            _targetSelectionOutline = GetNodeOrNull<Line2D>("TargetSelectionOutline");
        }

        if (_targetSelectionOutline == null)
        {
            return;
        }

        _targetSelectionOutline.Visible = isVisible;
        if (isVisible)
        {
            _targetSelectionOutline.DefaultColor = outlineColor;
            _targetSelectionOutline.Width = outlineWidth;
        }
    }

    private bool TryGetBaseSpriteScale(out Vector2 baseSpriteScale)
    {
        if (_visualScaleBaseMap.Count == 0)
        {
            CacheVisualScaleTargets();
        }

        // Sprite2D 是卡面缩放比例的基准节点，其他内部节点都据此计算相同的相对倍率。
        Node spriteNode = GetNodeOrNull<Node>("Sprite2D");
        if (spriteNode != null && _visualScaleBaseMap.TryGetValue(spriteNode, out baseSpriteScale))
        {
            return true;
        }

        baseSpriteScale = Vector2.One;
        return false;
    }

    private void AppendVisualScaleProperties(Tween tween, Vector2 targetSpriteScale, double duration)
    {
        if (!TryGetBaseSpriteScale(out Vector2 baseSpriteScale))
        {
            return;
        }

        // Sprite2D 引用用于准确识别基准卡面，避免以节点名称比较导致重命名后缩放比例失效。
        Node spriteNode = GetNodeOrNull<Node>("Sprite2D");
        if (spriteNode == null)
        {
            return;
        }

        // 缩放比例会同步应用到卡名、属性和状态栏，使它们围绕卡面保持原有的相对布局。
        Vector2 ratio = new(
            baseSpriteScale.X != 0f ? targetSpriteScale.X / baseSpriteScale.X : 1f,
            baseSpriteScale.Y != 0f ? targetSpriteScale.Y / baseSpriteScale.Y : 1f
        );

        foreach (var pair in _visualScaleBaseMap)
        {
            // 卡面使用绝对目标缩放，内部节点使用与基准卡面相同的倍率。
            Vector2 targetScale = pair.Key == spriteNode
                ? targetSpriteScale
                : new Vector2(pair.Value.X * ratio.X, pair.Value.Y * ratio.Y);
            tween.TweenProperty(pair.Key, "scale", targetScale, duration);

            if (_visualPositionBaseMap.TryGetValue(pair.Key, out Vector2 basePosition))
            {
                // 同步位置可让卡面内部文字围绕同一中心缩放，而血条不在缓存内所以不会被移动。
                Vector2 targetPosition = new(basePosition.X * ratio.X, basePosition.Y * ratio.Y);
                tween.TweenProperty(pair.Key, "position", targetPosition, duration);
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
        StopTargetSelectionPulse();
        if (!TryGetBaseSpriteScale(out _))
        {
            return;
        }

        if (_visualScaleTween != null && _visualScaleTween.IsRunning())
        {
            _visualScaleTween.Kill();
        }

        _visualScaleTween = CreateTween().SetParallel(true);
        AppendVisualScaleProperties(_visualScaleTween, targetSpriteScale, duration);
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
