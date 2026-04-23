using Godot;
using System;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.resources.interaction;
using CUSGA.resources.item;

namespace CUSGA.entities;

public partial class BoardCardView : Area2D
{
    [Signal] public delegate void ClickedEventHandler(BoardCardView card);
    [Signal] public delegate void HoverStartedEventHandler(BoardCardView card);
    [Signal] public delegate void HoverEndedEventHandler(BoardCardView card);

    private BoardCardState _state;

    private Sprite2D _iconSprite;
    private Label _titleLabel;
    private Label _amountLabel;
    private Tween _activeTween;

    public override void _Ready()
    {
        _iconSprite = GetNode<Sprite2D>("Icon");
        _titleLabel = GetNode<Label>("Title");
        _amountLabel = GetNode<Label>("Amount");

        InputPickable = true;

        MouseEntered += OnMouseEnteredInternal;
        MouseExited += OnMouseExitedInternal;
    }

    public override void _ExitTree()
    {
        StopActiveTween();
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
    }

    public override void _InputEvent(Viewport viewport, InputEvent @event, int shapeIdx)
    {
        if (@event is InputEventMouseButton
            {
                Pressed: true,
                ButtonIndex: MouseButton.Left
            })
        {
            EmitSignal(SignalName.Clicked, this);
        }
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

        _activeTween = GetTree().CreateTween();
        _activeTween.SetParallel(true);

        _activeTween.TweenProperty(this, "global_position", targetPosition, 0.35f)
            .SetTrans(Tween.TransitionType.Circ)
            .SetEase(Tween.EaseType.Out);

        _activeTween.TweenProperty(this, "scale", Vector2.One, 0.35f)
            .SetTrans(Tween.TransitionType.Back)
            .SetEase(Tween.EaseType.Out);

        _activeTween.Finished += OnScatterFinished;
    }

    private void OnScatterFinished()
    {
        InputPickable = true;
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

    private void StopActiveTween()
    {
        if (_activeTween != null && _activeTween.IsValid())
        {
            _activeTween.Kill();
            _activeTween = null;
        }
    }
}
