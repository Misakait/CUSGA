using System;
using System.Collections.Generic;
using Godot;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.core.application;
using CUSGA.resources.interaction.operations;

namespace CUSGA.core.gameplay;

public partial class WorldInteractionCoordinator : Node
{
    [Export] public NodePath BoardControllerPath { get; set; } = null!;
    [Export] public NodePath GameplayPortPath { get; set; } = null!;
    [Export] public NodePath BackpackFlyTargetPath { get; set; } = null!;
    [Export] public NodePath EncounterManagerPath { get; set; } = null!;

    private EncounterManager _encounterManager;
    private BoardController _boardController = null!;
    private GameplayPort _gameplayPort = null!;
    private Control _backpackFlyTarget;
    private Node _globalEventBus;

    public override void _Ready()
    {
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _backpackFlyTarget = GetNodeOrNull<Control>(BackpackFlyTargetPath);
        _globalEventBus = GetNodeOrNull<Node>("/root/GlobalEventBus");
        _encounterManager = GetNode<EncounterManager>(EncounterManagerPath);
        _boardController.CardClicked += OnBoardCardClicked;
    }

    public override void _ExitTree()
    {
        if (_boardController != null)
        {
            _boardController.CardClicked -= OnBoardCardClicked;
        }
    }

    private void OnBoardCardClicked(BoardCardView card)
    {
        ArgumentNullException.ThrowIfNull(card);

        ItemStack loot = card.GetLootStackOrNull();
        if (loot != null)
        {
            HandleLootCardClicked(card, loot);
            return;
        }

        TerrainInstance terrain = card.GetTerrainInstanceOrNull();
        if (terrain != null)
        {
            HandleTerrainCardClicked(card, terrain);
        }
    }

    private void HandleLootCardClicked(BoardCardView card, ItemStack stack)
    {
        bool success = _gameplayPort.TryAddItemToInventory(stack);
        if (!success)
        {
            return;
        }

        if (_backpackFlyTarget == null)
        {
            _boardController.RemoveCard(card);
            return;
        }

        Vector2 target = _backpackFlyTarget.GetGlobalRect().GetCenter();
        card.PlayFlyTo(target, () => _boardController.RemoveCard(card));
    }

    private void HandleTerrainCardClicked(BoardCardView card, TerrainInstance terrain)
    {
        GD.Print($"[WorldInteractionCoordinator] Click terrain: {terrain.TerrainData.CardName}");
        TerrainInteraction interaction = terrain.TerrainData?.InteractionBehavior;
        if (interaction == null)
        {
            return;
        }
        GD.Print($"[WorldInteractionCoordinator] Build ops from {interaction.GetType().Name}");
        var buildCtx = new TerrainInteractionBuildContext
        {
            Player = _gameplayPort.Player,
            Card = card,
            Terrain = terrain
        };

        IReadOnlyList<TerrainOp> ops = interaction.BuildOps(buildCtx);

        var worldCtx = new WorldInteractionContext
        {
            GameplayPort = _gameplayPort,
            BoardController = _boardController,
            Card = card,
            Terrain = terrain,
            GlobalEventBus = _globalEventBus,
            BackpackFlyTarget = _backpackFlyTarget,
            EncounterManager = _encounterManager,
        };
        GD.Print($"[WorldInteractionCoordinator] Ops count = {ops.Count}");
        foreach (TerrainOp op in ops)
        {
            op.Apply(worldCtx);
        }
    }
}
