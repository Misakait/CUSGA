using Godot;
using System;
using System.Collections.Generic;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;

namespace CUSGA.core.board;

public partial class BoardController : Node2D
{
    [Signal] public delegate void CardSpawnedEventHandler(BoardCardView card);
    [Signal] public delegate void CardRemovedEventHandler(BoardCardView card);
    [Signal] public delegate void CardClickedEventHandler(BoardCardView card);
    [Signal] public delegate void CardPressedEventHandler(BoardCardView card);
    [Signal] public delegate void CardReleasedEventHandler(BoardCardView card);
    [Signal] public delegate void CardHoverStartedEventHandler(BoardCardView card);
    [Signal] public delegate void CardHoverEndedEventHandler(BoardCardView card);

    [Export] public PackedScene CardViewScene { get; set; }
    [Export] public NodePath CardsRootPath { get; set; }

    [Export] public float ScatterRadiusMin { get; set; } = 40f;
    [Export] public float ScatterRadiusMax { get; set; } = 90f;

    private Node2D _cardsRoot;
    private readonly RandomNumberGenerator _rng = new();
    private readonly HashSet<BoardCardView> _activeCards = [];
    private readonly Dictionary<Vector2I, BoardCardView> _terrainCardsByLocalGrid = [];

    public override void _Ready()
    {
        if (CardViewScene == null)
        {
            throw new InvalidOperationException("BoardController.CardViewScene 未设置。");
        }

        _cardsRoot = CardsRootPath.IsEmpty ? this : GetNode<Node2D>(CardsRootPath);
    }

    public override void _ExitTree()
    {
        foreach (BoardCardView card in _activeCards)
        {
            if (IsInstanceValid(card))
            {
                DisconnectCardSignals(card);
            }
        }

        _activeCards.Clear();
        _terrainCardsByLocalGrid.Clear();
    }

    public BoardCardView SpawnTerrainCard(TerrainInstance terrainInstance, Vector2 globalPosition)
    {
        ArgumentNullException.ThrowIfNull(terrainInstance);
        if (_terrainCardsByLocalGrid.ContainsKey(terrainInstance.LocalGridPos))
        {
            throw new InvalidOperationException($"Grid {terrainInstance.LocalGridPos} 已经存在地形卡。");
        }
        GD.Print($"[BoardController] Spawn terrain card at {globalPosition}, localGrid={terrainInstance.LocalGridPos}");

        var state = new TerrainBoardCardState(terrainInstance);
        var card = SpawnCard(state, globalPosition);

        _terrainCardsByLocalGrid[terrainInstance.LocalGridPos] = card;
        return card;
    }

    public BoardCardView SpawnLootCard(ItemStack stack, Vector2 globalPosition)
    {
        ArgumentNullException.ThrowIfNull(stack);

        var state = new LootBoardCardState(stack);
        return SpawnCard(state, globalPosition);
    }

    public void SpawnLootCards(Godot.Collections.Array<ItemStack> stacks, Vector2 spawnOrigin)
    {
        ArgumentNullException.ThrowIfNull(stacks);

        foreach (ItemStack stack in stacks)
        {
            SpawnSingleLootWithScatter(stack, spawnOrigin);
        }
    }

    public void RemoveCard(BoardCardView card)
    {
        GD.Print($"Removing card: {card?.GetCardData()?.CardName}");
        if (card == null || !IsInstanceValid(card))
        {
            return;
        }

        if (card.GetTerrainInstanceOrNull() is { } terrain)
        {
            _terrainCardsByLocalGrid.Remove(terrain.LocalGridPos);
        }

        DisconnectCardSignals(card);
        _activeCards.Remove(card);

        EmitSignal(SignalName.CardRemoved, card);
        card.QueueFree();
        GD.Print($"Removed card: {card?.GetCardData()?.CardName}");
    }

    public void ClearAllCards()
    {
        var snapshot = new List<BoardCardView>(_activeCards);

        foreach (BoardCardView card in snapshot)
        {
            RemoveCard(card);
        }
        _terrainCardsByLocalGrid.Clear();
    }

    public bool TryGetTerrainCardByLocalGrid(Vector2I gridPos, out BoardCardView card)
    {
        return _terrainCardsByLocalGrid.TryGetValue(gridPos, out card);
    }

    public BoardCardView GetTerrainCardByLocalGridOrNull(Vector2I gridPos)
    {
        return _terrainCardsByLocalGrid.TryGetValue(gridPos, out var card) ? card : null;
    }

    public bool HasTerrainCardAtLocalGrid(Vector2I gridPos)
    {
        return _terrainCardsByLocalGrid.ContainsKey(gridPos);
    }

    /// <summary>
    /// 获取当前棋盘卡牌快照。
    /// </summary>
    /// <returns>返回当前仍由棋盘控制器持有的卡牌列表。</returns>
    public IReadOnlyList<BoardCardView> GetActiveCardsSnapshot()
    {
        return [.. _activeCards];
    }

    private void SpawnSingleLootWithScatter(ItemStack stack, Vector2 spawnOrigin)
    {
        Vector2 target = spawnOrigin + RandomDirection() * _rng.RandfRange(ScatterRadiusMin, ScatterRadiusMax);

        BoardCardView card = SpawnLootCard(stack, target);
        card.PlayScatterFrom(spawnOrigin, target);
    }

    private BoardCardView SpawnCard(BoardCardState state, Vector2 globalPosition)
    {
        BoardCardView card = CardViewScene.Instantiate<BoardCardView>();
        _cardsRoot.AddChild(card);

        card.GlobalPosition = globalPosition;
        card.Bind(state);

        ConnectCardSignals(card);
        _activeCards.Add(card);

        EmitSignal(SignalName.CardSpawned, card);
        return card;
    }

    private void ConnectCardSignals(BoardCardView card)
    {
        card.Clicked += OnCardClicked;
        card.Pressed += OnCardPressed;
        card.Released += OnCardReleased;
        card.HoverStarted += OnCardHoverStarted;
        card.HoverEnded += OnCardHoverEnded;
    }

    private void DisconnectCardSignals(BoardCardView card)
    {
        card.Clicked -= OnCardClicked;
        card.Pressed -= OnCardPressed;
        card.Released -= OnCardReleased;
        card.HoverStarted -= OnCardHoverStarted;
        card.HoverEnded -= OnCardHoverEnded;
    }

    private void OnCardClicked(BoardCardView card)
    {
        GD.Print($"Card clicked: {card.GetCardData().CardName}");
        EmitSignal(SignalName.CardClicked, card);
    }

    private void OnCardPressed(BoardCardView card)
    {
        EmitSignal(SignalName.CardPressed, card);
    }

    private void OnCardReleased(BoardCardView card)
    {
        EmitSignal(SignalName.CardReleased, card);
    }

    private void OnCardHoverStarted(BoardCardView card)
    {
        EmitSignal(SignalName.CardHoverStarted, card);
    }

    private void OnCardHoverEnded(BoardCardView card)
    {
        EmitSignal(SignalName.CardHoverEnded, card);
    }

    private Vector2 RandomDirection()
    {
        float angle = _rng.RandfRange(0f, Mathf.Tau);
        return new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
    }
}
