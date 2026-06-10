using Godot;
using System;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.resources.interaction;
using CUSGA.resources.item;

namespace CUSGA.entities;

/// <summary>
/// 展示棋盘上的地形卡和掉落卡，并把鼠标输入转换为棋盘卡牌信号。
/// </summary>
public partial class BoardCardView : Area2D
{
    [Signal] public delegate void ClickedEventHandler(BoardCardView card);
    [Signal] public delegate void PressedEventHandler(BoardCardView card);
    [Signal] public delegate void ReleasedEventHandler(BoardCardView card);
    [Signal] public delegate void HoverStartedEventHandler(BoardCardView card);
    [Signal] public delegate void HoverEndedEventHandler(BoardCardView card);

    /// <summary>
    /// 地形卡静止显示时的整体缩放倍率。
    /// </summary>
    [Export(PropertyHint.Range, "1,8,0.1,or_greater")]
    public float TerrainCardRestingScale { get; set; } = 3f;

    private BoardCardState _state;

    private Sprite2D _iconSprite;
    private Label _titleLabel;
    private Label _amountLabel;
    private ProgressBar _holdProgressBar;
    private Tween _activeTween;
    private Tween _holdTween;
    private Action _holdCompleted;
    private bool _interactionDisabled;

    public override void _Ready()
    {
        _iconSprite = GetNode<Sprite2D>("Icon");
        _titleLabel = GetNode<Label>("Title");
        _amountLabel = GetNode<Label>("Amount");
        _holdProgressBar = GetNode<ProgressBar>("HoldProgress");

        InputPickable = true;
        ResetHoldProgress();

        MouseEntered += OnMouseEnteredInternal;
        MouseExited += OnMouseExitedInternal;
    }

    public override void _ExitTree()
    {
        StopActiveTween();
        CancelHoldProgress();
    }

    internal BoardCardState State => _state;

    public BaseCardData GetCardData()
    {
        return _state?.CardData;
    }

    public bool IsLootCard()
    {
        return _state is LootBoardCardState;
    }

    public bool IsTerrainCard()
    {
        return _state is TerrainBoardCardState;
    }

    public ItemStack GetLootStackOrNull()
    {
        return (_state as LootBoardCardState)?.LootStack;
    }

    public TerrainInstance GetTerrainInstanceOrNull()
    {
        return (_state as TerrainBoardCardState)?.TerrainInstance;
    }

    public TerrainCardData GetTerrainDataOrNull()
    {
        return (_state as TerrainBoardCardState)?.TerrainData;
    }

    public void Bind(BoardCardState state)
    {
        _state = state ?? throw new ArgumentNullException(nameof(state));
        RefreshView();
    }

    public void RefreshView()
    {
        if (_state == null)
        {
            throw new InvalidOperationException("BoardCardView 在 Bind 之前不能刷新。");
        }

        BaseCardData cardData = _state.CardData;

        _titleLabel.Text = cardData.CardName ?? string.Empty;
        _iconSprite.Texture = cardData.CardIcon;
        Scale = GetRestingScale();

        if (_state is LootBoardCardState lootState && lootState.LootStack.Amount > 1)
        {
            _amountLabel.Visible = true;
            _amountLabel.Text = lootState.LootStack.Amount.ToString();
        }
        else
        {
            _amountLabel.Visible = false;
            _amountLabel.Text = string.Empty;
        }

        ApplyInteractionDisabledVisual();
    }

    public override void _InputEvent(Viewport viewport, InputEvent @event, int shapeIdx)
    {
        if (@event is not InputEventMouseButton
            {
                ButtonIndex: MouseButton.Left
            } mouseButton)
        {
            return;
        }

        if (mouseButton.Pressed)
        {
            EmitSignal(SignalName.Pressed, this);
            if (!_interactionDisabled)
            {
                EmitSignal(SignalName.Clicked, this);
            }
        }
        else
        {
            EmitSignal(SignalName.Released, this);
        }

        viewport.SetInputAsHandled();
    }

    private void OnMouseEnteredInternal()
    {
        EmitSignal(SignalName.HoverStarted, this);
    }

    private void OnMouseExitedInternal()
    {
        EmitSignal(SignalName.HoverEnded, this);
    }

    public void PlayScatterFrom(Vector2 spawnOrigin, Vector2 targetPosition)
    {
        StopActiveTween();

        GlobalPosition = spawnOrigin;
        Scale = Vector2.Zero;
        Rotation = 0f;
        InputPickable = false;
        Vector2 restingScale = GetRestingScale();

        _activeTween = GetTree().CreateTween();
        _activeTween.SetParallel(true);

        _activeTween.TweenProperty(this, "global_position", targetPosition, 0.35f)
            .SetTrans(Tween.TransitionType.Circ)
            .SetEase(Tween.EaseType.Out);

        _activeTween.TweenProperty(this, "scale", restingScale, 0.35f)
            .SetTrans(Tween.TransitionType.Back)
            .SetEase(Tween.EaseType.Out);

        _activeTween.Finished += OnScatterFinished;
    }

    private void OnScatterFinished()
    {
        InputPickable = !_interactionDisabled;
    }

    public void PlayFlyTo(Vector2 targetPosition, Action onFinished = null)
    {
        StopActiveTween();

        InputPickable = false;
        ZIndex = 1000;

        _activeTween = GetTree().CreateTween();
        _activeTween.SetParallel(true);

        _activeTween.TweenProperty(this, "global_position", targetPosition, 0.30f)
            .SetTrans(Tween.TransitionType.Sine)
            .SetEase(Tween.EaseType.In);

        _activeTween.TweenProperty(this, "scale", Vector2.Zero, 0.30f)
            .SetTrans(Tween.TransitionType.Sine)
            .SetEase(Tween.EaseType.In);

        if (onFinished != null)
        {
            _activeTween.Finished += onFinished;
        }
    }

    public void SetHighlighted(bool highlighted)
    {

    }

    /// <summary>
    /// 设置当前卡牌是否因资源冷却等原因禁用交互。
    /// </summary>
    /// <param name="disabled">为 true 时卡牌变灰并关闭输入。</param>
    public void SetInteractionDisabled(bool disabled)
    {
        _interactionDisabled = disabled;
        if (disabled)
        {
            CancelHoldProgress();
        }
        ApplyInteractionDisabledVisual();
    }

    /// <summary>
    /// 开始显示长按进度，并在进度完成后调用回调。
    /// </summary>
    /// <param name="durationSeconds">长按需要持续的真实秒数。</param>
    /// <param name="onCompleted">进度完成后的回调。</param>
    public void StartHoldProgress(float durationSeconds, Action onCompleted)
    {
        if (_interactionDisabled)
        {
            return;
        }

        CancelHoldProgress();
        _holdCompleted = onCompleted;
        _holdProgressBar.Visible = true;
        _holdProgressBar.Value = 0.0;

        if (durationSeconds <= 0.0f)
        {
            CompleteHoldProgress();
            return;
        }

        _holdTween = GetTree().CreateTween();
        _holdTween.TweenProperty(_holdProgressBar, "value", 1.0, durationSeconds)
            .SetTrans(Tween.TransitionType.Linear)
            .SetEase(Tween.EaseType.InOut);
        _holdTween.Finished += CompleteHoldProgress;
    }

    /// <summary>
    /// 取消正在进行的长按采集进度。
    /// </summary>
    public void CancelHoldProgress()
    {
        if (_holdTween != null && _holdTween.IsValid())
        {
            _holdTween.Kill();
        }

        _holdTween = null;
        _holdCompleted = null;
        ResetHoldProgress();
    }

    private Vector2 GetRestingScale()
    {
        // 地形图标目前是 32x32 像素；根节点缩放可以同步放大图标、文字和点击范围。
        return _state is TerrainBoardCardState
            ? Vector2.One * TerrainCardRestingScale
            : Vector2.One;
    }

    private void StopActiveTween()
    {
        if (_activeTween != null && _activeTween.IsValid())
        {
            _activeTween.Kill();
            _activeTween = null;
        }
    }

    private void CompleteHoldProgress()
    {
        Action completed = _holdCompleted;
        _holdTween = null;
        _holdCompleted = null;
        ResetHoldProgress();
        completed?.Invoke();
    }

    private void ResetHoldProgress()
    {
        if (_holdProgressBar == null)
        {
            return;
        }

        _holdProgressBar.Value = 0.0;
        _holdProgressBar.Visible = false;
    }

    private void ApplyInteractionDisabledVisual()
    {
        InputPickable = !_interactionDisabled;
        Modulate = _interactionDisabled
            ? new Color(0.45f, 0.45f, 0.45f, 1.0f)
            : Colors.White;
    }
}
