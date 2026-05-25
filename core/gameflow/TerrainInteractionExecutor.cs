using System.Collections.Generic;
using Godot;
using Godot.Collections;
using CUSGA.core.application;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using CUSGA.resources.interaction.operations;
using CUSGA.resources.monsters;

namespace CUSGA.core.gameflow;

public sealed class TerrainInteractionExecutor(
    GameplayPort gameplayPort,
    BoardController boardController,
    EncounterManager encounterManager)
{
    public void Execute(BoardCardView card, TerrainInstance terrain)
    {
        GD.Print($"[TerrainInteractionExecutor] Click terrain: {terrain.TerrainData.CardName}");
        TerrainInteraction interaction = terrain.TerrainData?.InteractionBehavior;
        if (interaction == null)
        {
            return;
        }

        GD.Print($"[TerrainInteractionExecutor] Build ops from {interaction.GetType().Name}");
        var buildCtx = new TerrainInteractionBuildContext
        {
            Player = gameplayPort.Player,
            Terrain = terrain
        };

        IReadOnlyList<TerrainOp> ops = interaction.BuildOps(buildCtx);
        var worldCtx = new WorldInteractionContext
        {
            Gameplay = new GameplayInteractionPort(gameplayPort),
            Board = new BoardInteractionPort(boardController, card),
            Encounters = new EncounterInteractionPort(encounterManager, gameplayPort),
            Terrain = terrain,
            SourceGlobalPosition = card.GlobalPosition,
        };

        GD.Print($"[TerrainInteractionExecutor] Ops count = {ops.Count}");
        foreach (TerrainOp op in ops)
        {
            op.Apply(worldCtx);
        }
    }

    private sealed class GameplayInteractionPort(GameplayPort gameplayPort) : IInteractionGameplayPort
    {
        public void RequestOpenFarmingPanel(TerrainInstance terrain)
        {
            gameplayPort.RequestOpenFarmingPanel(terrain);
        }

        public void RequestOpenWarehouse()
        {
            gameplayPort.RequestOpenWarehouse();
        }

        public void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message)
        {
            gameplayPort.RequestEncounter(terrain, monster, message);
        }

        public void RequestEncounter(TerrainInstance terrain, Array<MonsterData> monsters, string message)
        {
            gameplayPort.RequestEncounter(terrain, monsters, message);
        }
    }

    private sealed class BoardInteractionPort(BoardController boardController, BoardCardView sourceCard) : IInteractionBoardPort
    {
        public void SpawnLootCards(Array<ItemStack> drops, Vector2 spawnOrigin)
        {
            boardController.SpawnLootCards(drops, spawnOrigin);
        }

        public void RemoveSourceCard()
        {
            boardController.RemoveCard(sourceCard);
        }
    }

    private sealed class EncounterInteractionPort(
        EncounterManager encounterManager,
        GameplayPort gameplayPort) : IInteractionEncounterPort
    {
        public GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag)
        {
            float encounterChanceMultiplier =
                gameplayPort.Player?.Equipment?.GetNightEncounterChanceMultiplier() ?? 1.0f;
            return encounterManager.ResolveGatheringEncounter(resourceTag, encounterChanceMultiplier);
        }
    }
}
