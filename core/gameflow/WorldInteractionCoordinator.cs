using System;
using Godot;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.core.application;
using CUSGA.resources.item.card;
using CUSGA.resources.monsters;
using Godot.Collections;

namespace CUSGA.core.gameflow;

public partial class WorldInteractionCoordinator : Node
{
    [Export] public NodePath BoardControllerPath { get; set; } = null!;
    [Export] public NodePath GameplayPortPath { get; set; } = null!;
    [Export] public NodePath BackpackFlyTargetPath { get; set; } = null!;
    [Export] public NodePath EncounterManagerPath { get; set; } = null!;
    public NodePath ScreenTransitionsPath { get; set; } = new("/root/ScreenTransitions");

    [ExportGroup("World View")]
    [Export] public NodePath WorldRootPath { get; set; } = new("../..");
    [Export] public NodePath MapSystemPath { get; set; } = new("../../MapSystem");
    [Export] public NodePath MapCanvasLayerPath { get; set; } = new("../../MapSystem/CanvasLayer");
    [Export] public NodePath HudLayerPath { get; set; } = new("../../UI/HUDLayer");

    private EncounterManager _encounterManager;
    private WorldCombatScenePresenter _combatScenePresenter = null!;
    private TerrainInteractionExecutor _terrainInteractionExecutor = null!;
    private BoardController _boardController = null!;
    private GameplayPort _gameplayPort = null!;
    private Control _backpackFlyTarget;

    public override void _Ready()
    {
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _backpackFlyTarget = GetNodeOrNull<Control>(BackpackFlyTargetPath);
        _encounterManager = GetNode<EncounterManager>(EncounterManagerPath);
        Node screenTransitions = GetNodeOrNull<Node>(ScreenTransitionsPath);
        Node worldRoot = GetNode<Node>(WorldRootPath);
        Node mapSystem = GetNodeOrNull<Node>(MapSystemPath);
        var worldViewVisibility = new WorldViewVisibilityController(
            this,
            BoardControllerPath,
            MapSystemPath,
            MapCanvasLayerPath,
            HudLayerPath
        );
        _combatScenePresenter = new WorldCombatScenePresenter(
            worldRoot,
            mapSystem,
            new ScreenTransitionAdapter(this, screenTransitions),
            worldViewVisibility
        );
        _terrainInteractionExecutor = new TerrainInteractionExecutor(
            _gameplayPort,
            _boardController,
            _encounterManager
        );

        _boardController.CardClicked += OnBoardCardClicked;
        _gameplayPort.EncounterRequested += OnEncounterRequested;
    }

    public override void _ExitTree()
    {
        if (_boardController != null)
        {
            _boardController.CardClicked -= OnBoardCardClicked;
        }
        if (_gameplayPort != null)
        {
            _gameplayPort.EncounterRequested -= OnEncounterRequested;
        }
    }

    private async void OnEncounterRequested(TerrainInstance terrain, Array<SkillCardData> battleDeck, Array<MonsterData> monsters, string message)
    {
        await _combatScenePresenter.EnterCombatAsync(battleDeck, monsters);
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
        _terrainInteractionExecutor.Execute(card, terrain);
    }
}
