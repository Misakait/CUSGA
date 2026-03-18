using Godot;
using System;

namespace CUSGA.resources.talents;

public partial class TalentCard : Control
{
    public event Action<TalentData> OnCardClicked;

    private TalentData _talentData;
    private Tween _hoverTween;

    [Export] private Label _titleLabel;
    [Export] private RichTextLabel _descLabel;
    [Export] private Button _clickArea;
    [Export] private TextureRect _texture;

    public override void _Ready()
    {
        _clickArea.Pressed += OnPressed;
        _clickArea.MouseEntered += OnHoverEnter;
        _clickArea.MouseExited += OnHoverExit;

        // 将缩放轴心钉在卡牌的“底部正中心”
        PivotOffset = new Vector2(Size.X / 2, Size.Y);
    }

    private void OnHoverEnter()
    {
        GD.Print("TalentCard hovered: " + _talentData.TalentName);
        // 杀死还在运行的旧动画，防止玩家“帕金森式”狂晃鼠标导致动画冲突抽搐
        _hoverTween?.Kill();
        _hoverTween = CreateTween();

        _hoverTween.TweenProperty(this, "scale", new Vector2(1.05f, 1.05f), 0.15f)
                   .SetTrans(Tween.TransitionType.Back)
                   .SetEase(Tween.EaseType.Out);

        // 悬浮时让卡牌跑到最顶层，防止被旁边放大的卡牌挡住边缘
        ZIndex = 1;
    }

    private void OnHoverExit()
    {
        _hoverTween?.Kill();
        _hoverTween = CreateTween();

        _hoverTween.TweenProperty(this, "scale", Vector2.One, 0.15f)
                   .SetTrans(Tween.TransitionType.Quad)
                   .SetEase(Tween.EaseType.Out);

        ZIndex = 0;
    }

    private void OnPressed()
    {
        GD.Print("TalentCard clicked: " + _talentData.TalentName);
        if (_talentData != null) OnCardClicked?.Invoke(_talentData);
    }

    public void Initialize(TalentData data)
    {
        _talentData = data;

        if (_titleLabel != null) _titleLabel.Text = data.TalentName;
        if (_descLabel != null) _descLabel.Text = data.Description;
        if (_texture != null) _texture.Texture = data.TalentTexture;
    }
}
