using Godot;
using System;
using System.Collections.Generic;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;

namespace CUSGA.core.board;

public partial class BoardController : Node2D
{
    private const string BoardCardStateScriptPath = "res://core/board/board_card_state.gd";

    [Signal] public delegate void CardSpawnedEventHandler(Node2D card);
    [Signal] public delegate void CardRemovedEventHandler(Node2D card);
    [Signal] public delegate void CardClickedEventHandler(Node2D card);
    [Signal] public delegate void CardPressedEventHandler(Node2D card);
    [Signal] public delegate void CardReleasedEventHandler(Node2D card);
    [Signal] public delegate void CardHoverStartedEventHandler(Node2D card);
    [Signal] public delegate void CardHoverEndedEventHandler(Node2D card);

    [Export] public PackedScene CardViewScene { get; set; }
    [Export] public NodePath CardsRootPath { get; set; }

    [Export] public float ScatterRadiusMin { get; set; } = 40f;
    [Export] public float ScatterRadiusMax { get; set; } = 90f;

    private Node2D _cardsRoot;
    private readonly RandomNumberGenerator _rng = new();
    private readonly HashSet<Node2D> _activeCards = [];
    private readonly Dictionary<Vector2I, Node2D> _terrainCardsByLocalGrid = [];

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
        foreach (Node2D card in _activeCards)
        {
            if (IsInstanceValid(card))
            {
                DisconnectCardSignals(card);
            }
        }

        _activeCards.Clear();
        _terrainCardsByLocalGrid.Clear();
    }

    public Node2D SpawnTerrainCard(TerrainInstance terrainInstance, Vector2 globalPosition)
    {
        ArgumentNullException.ThrowIfNull(terrainInstance);
        if (_terrainCardsByLocalGrid.ContainsKey(terrainInstance.LocalGridPos))
        {
            throw new InvalidOperationException($"Grid {terrainInstance.LocalGridPos} 已经存在地形卡。");
        }
        GD.Print($"[BoardController] Spawn terrain card at {globalPosition}, localGrid={terrainInstance.LocalGridPos}");

        RefCounted state = CreateTerrainState(terrainInstance);
        var card = SpawnCard(state, globalPosition);

        _terrainCardsByLocalGrid[terrainInstance.LocalGridPos] = card;
        return card;
    }

    /// <summary>
    /// 在指定位置生成一张掉落卡，并保留原物品堆叠引用。
    /// </summary>
    /// <param name="stack">旧 C# 或 GDScript ItemStack。</param>
    /// <param name="globalPosition">掉落卡的目标全局坐标。</param>
    /// <returns>新生成的掉落卡视图。</returns>
    public Node2D SpawnLootCard(RefCounted stack, Vector2 globalPosition)
    {
        ArgumentNullException.ThrowIfNull(stack);

        RefCounted state = CreateLootState(stack);
        return SpawnCard(state, globalPosition);
    }

    /// <summary>
    /// 从同一原点散射生成一组跨语言物品堆叠对应的掉落卡。
    /// </summary>
    /// <param name="stacks">旧 C# 与 GDScript ItemStack 可混合组成的非泛型数组。</param>
    /// <param name="spawnOrigin">散射动画的全局起点。</param>
    public void SpawnLootCards(Godot.Collections.Array stacks, Vector2 spawnOrigin)
    {
        ArgumentNullException.ThrowIfNull(stacks);

        foreach (Variant value in stacks)
        {
            // 非泛型数组是跨语言封送边界；这里只接纳两种实现共同继承的 RefCounted。
            if (value.AsGodotObject() is RefCounted stack
                && ItemStackProtocol.TryRead(stack, out _, out _))
            {
                SpawnSingleLootWithScatter(stack, spawnOrigin);
            }
        }
    }

    public void RemoveCard(Node2D card)
    {
        GD.Print($"Removing card: {card?.Call("GetCardDisplayName").AsString()}");
        if (card == null || !IsInstanceValid(card))
        {
            return;
        }

        if (card.Call("GetTerrainInstanceOrNull").AsGodotObject() is TerrainInstance terrain)
        {
            _terrainCardsByLocalGrid.Remove(terrain.LocalGridPos);
        }

        DisconnectCardSignals(card);
        _activeCards.Remove(card);

        EmitSignal(SignalName.CardRemoved, card);
        card.QueueFree();
        GD.Print($"Removed card: {card?.Call("GetCardDisplayName").AsString()}");
    }

    public void ClearAllCards()
    {
        var snapshot = new List<Node2D>(_activeCards);

        foreach (Node2D card in snapshot)
        {
            RemoveCard(card);
        }
        _terrainCardsByLocalGrid.Clear();
    }

    public bool TryGetTerrainCardByLocalGrid(Vector2I gridPos, out Node2D card)
    {
        return _terrainCardsByLocalGrid.TryGetValue(gridPos, out card);
    }

    public Node2D GetTerrainCardByLocalGridOrNull(Vector2I gridPos)
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
    public IReadOnlyList<Node2D> GetActiveCardsSnapshot()
    {
        return [.. _activeCards];
    }

    private void SpawnSingleLootWithScatter(RefCounted stack, Vector2 spawnOrigin)
    {
        Vector2 target = spawnOrigin + RandomDirection() * _rng.RandfRange(ScatterRadiusMin, ScatterRadiusMax);

        Node2D card = SpawnLootCard(stack, target);
        card.Call("PlayScatterFrom", spawnOrigin, target);
    }

    private Node2D SpawnCard(RefCounted state, Vector2 globalPosition)
    {
        Node2D card = CardViewScene.Instantiate<Node2D>();
        _cardsRoot.AddChild(card);

        card.GlobalPosition = globalPosition;
        if (state.Call("IsTerrain").AsBool())
        {
            card.Call("InitializeTerrain", state.Call("GetTerrainInstanceOrNull").AsGodotObject());
        }
        else if (state.Call("IsLoot").AsBool())
        {
            card.Call("InitializeLoot", state.Call("GetLootStackOrNull").AsGodotObject());
        }
        else
        {
            throw new InvalidOperationException("未知棋盘卡状态，无法初始化视图。");
        }

        ConnectCardSignals(card);
        _activeCards.Add(card);

        EmitSignal(SignalName.CardSpawned, card);
        return card;
    }

    private static RefCounted CreateTerrainState(TerrainInstance terrainInstance)
    {
        RefCounted state = CreateState();
        if (!state.Call("InitializeTerrain", terrainInstance).AsBool())
        {
            throw new ArgumentException("TerrainInstance.TerrainData 不能为空。", nameof(terrainInstance));
        }

        return state;
    }

    private static RefCounted CreateLootState(RefCounted stack)
    {
        RefCounted state = CreateState();
        if (!state.Call("InitializeLoot", stack).AsBool())
        {
            throw new ArgumentException(
                "LootStack 必须提供非空 Item、正 Amount 与 IsEmpty 属性。",
                nameof(stack)
            );
        }

        return state;
    }

    private static RefCounted CreateState()
    {
        Script script = GD.Load<Script>(BoardCardStateScriptPath);
        if (script == null)
        {
            throw new InvalidOperationException($"无法加载棋盘卡状态脚本：{BoardCardStateScriptPath}");
        }

        Variant value = script.Call("new");
        if (value.AsGodotObject() is not RefCounted state)
        {
            throw new InvalidOperationException("棋盘卡状态脚本没有返回 RefCounted 实例。");
        }

        return state;
    }

    private void ConnectCardSignals(Node2D card)
    {
        card.Connect("Clicked", Callable.From<Node2D>(OnCardClicked));
        card.Connect("Pressed", Callable.From<Node2D>(OnCardPressed));
        card.Connect("Released", Callable.From<Node2D>(OnCardReleased));
        card.Connect("HoverStarted", Callable.From<Node2D>(OnCardHoverStarted));
        card.Connect("HoverEnded", Callable.From<Node2D>(OnCardHoverEnded));
    }

    private void DisconnectCardSignals(Node2D card)
    {
        DisconnectSignal(card, "Clicked", Callable.From<Node2D>(OnCardClicked));
        DisconnectSignal(card, "Pressed", Callable.From<Node2D>(OnCardPressed));
        DisconnectSignal(card, "Released", Callable.From<Node2D>(OnCardReleased));
        DisconnectSignal(card, "HoverStarted", Callable.From<Node2D>(OnCardHoverStarted));
        DisconnectSignal(card, "HoverEnded", Callable.From<Node2D>(OnCardHoverEnded));
    }

    private void OnCardClicked(Node2D card)
    {
        GD.Print($"Card clicked: {card.Call("GetCardDisplayName").AsString()}");
        EmitSignal(SignalName.CardClicked, card);
    }

    private void OnCardPressed(Node2D card)
    {
        EmitSignal(SignalName.CardPressed, card);
    }

    private void OnCardReleased(Node2D card)
    {
        EmitSignal(SignalName.CardReleased, card);
    }

    private void OnCardHoverStarted(Node2D card)
    {
        EmitSignal(SignalName.CardHoverStarted, card);
    }

    private void OnCardHoverEnded(Node2D card)
    {
        EmitSignal(SignalName.CardHoverEnded, card);
    }

    private Vector2 RandomDirection()
    {
        float angle = _rng.RandfRange(0f, Mathf.Tau);
        return new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
    }

    private static void DisconnectSignal(Node source, StringName signal, Callable callback)
    {
        if (source.IsConnected(signal, callback))
        {
            source.Disconnect(signal, callback);
        }
    }
}
