using System;
using Godot;
using CUSGA.core.autoloads;
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
    [Signal] public delegate void PassageGuardEncounterFinishedEventHandler(bool isVictory);

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
    private TimeSystem _timeSystem;
    private BoardCardView _holdingCard;
    private int _holdingEffectiveTimeCost;

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
        _boardController.CardPressed += OnBoardCardPressed;
        _boardController.CardReleased += OnBoardCardReleased;
        _boardController.CardSpawned += OnBoardCardSpawned;
        _gameplayPort.EncounterRequested += OnEncounterRequested;

        _timeSystem = TimeSystem.Instance;
        if (_timeSystem != null)
        {
            _timeSystem.TimeChanged += OnTimeChanged;
        }
    }

    public override void _ExitTree()
    {
        if (_boardController != null)
        {
            _boardController.CardClicked -= OnBoardCardClicked;
            _boardController.CardPressed -= OnBoardCardPressed;
            _boardController.CardReleased -= OnBoardCardReleased;
            _boardController.CardSpawned -= OnBoardCardSpawned;
        }
        if (_gameplayPort != null)
        {
            _gameplayPort.EncounterRequested -= OnEncounterRequested;
        }
        if (_timeSystem != null)
        {
            _timeSystem.TimeChanged -= OnTimeChanged;
        }
    }

    /// <summary>
    /// 监听全局鼠标松开，确保拖出卡牌范围后也会取消长按采集。
    /// </summary>
    /// <param name="event">Godot 输入事件。</param>
    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton
            {
                ButtonIndex: MouseButton.Left,
                Pressed: false
            })
        {
            CancelReusableGatheringHold();
        }
    }

    private async void OnEncounterRequested(TerrainInstance terrain, Array<SkillCardData> battleDeck, Array<MonsterData> monsters, string message)
    {
        await _combatScenePresenter.EnterCombatAsync(battleDeck, monsters);
    }

    /// <summary>
    /// 为地图通道驻守怪物发起战斗，并在战斗结束后发出结果信号。
    /// </summary>
    /// <param name="monsters">通道驻守 encounter 配置出的怪物数组。</param>
    public async void RequestPassageGuardEncounter(Array<MonsterData> monsters)
    {
        GD.Print("RequestPassageGuardEncounter: monsters = ", monsters);
        bool isVictory = await _combatScenePresenter.EnterCombatAndWaitForResultAsync(
            _gameplayPort.PlayerBattleDeck.GetSkillCards(),
            monsters ?? []
        );
        EmitSignal(SignalName.PassageGuardEncounterFinished, isVictory);
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
            if (terrain.TerrainData?.InteractionBehavior is ReusableGatheringInteraction)
            {
                return;
            }

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

    private void OnBoardCardPressed(BoardCardView card)
    {
        if (TryGetReusableGathering(card, out TerrainInstance terrain, out ReusableGatheringInteraction interaction))
        {
            StartReusableGatheringHold(card, terrain, interaction);
        }
    }

    private void OnBoardCardReleased(BoardCardView card)
    {
        if (card == _holdingCard)
        {
            CancelReusableGatheringHold();
        }
    }

    private void OnBoardCardSpawned(BoardCardView card)
    {
        if (TryGetReusableGathering(card, out TerrainInstance terrain, out ReusableGatheringInteraction interaction))
        {
            RefreshReusableGatheringCard(card, terrain, interaction, GetCurrentTotalTime());
        }
    }

    private void OnTimeChanged(
        int totalTimePassed,
        int currentDay,
        bool isNight,
        int phaseProgress,
        int phaseLength)
    {
        foreach (BoardCardView card in _boardController.GetActiveCardsSnapshot())
        {
            if (!IsInstanceValid(card)
                || !TryGetReusableGathering(card, out TerrainInstance terrain, out ReusableGatheringInteraction interaction))
            {
                continue;
            }

            RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
        }
    }

    private void StartReusableGatheringHold(
        BoardCardView card,
        TerrainInstance terrain,
        ReusableGatheringInteraction interaction)
    {
        CancelReusableGatheringHold();

        int totalTimePassed = GetCurrentTotalTime();
        RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
        if (!interaction.CanHarvest(terrain, totalTimePassed))
        {
            return;
        }

        _holdingCard = card;
        _holdingEffectiveTimeCost = interaction.GetEffectiveTimeCost(_gameplayPort.Player?.Equipment);
        float holdSeconds = _holdingEffectiveTimeCost / ReusableGatheringInteraction.GameTimePointsPerHoldSecond;
        card.StartHoldProgress(
            holdSeconds,
            () => CompleteReusableGatheringHold(card, terrain, interaction)
        );
    }

    private void CompleteReusableGatheringHold(
        BoardCardView card,
        TerrainInstance terrain,
        ReusableGatheringInteraction interaction)
    {
        if (_holdingCard != card)
        {
            return;
        }

        _holdingCard = null;
        int effectiveTimeCost = _holdingEffectiveTimeCost;
        _holdingEffectiveTimeCost = 0;
        int totalTimePassed = GetCurrentTotalTime();
        if (!interaction.CanHarvest(terrain, totalTimePassed))
        {
            RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
            return;
        }

        _terrainInteractionExecutor.Execute(card, terrain, effectiveTimeCost);
        RefreshReusableGatheringCard(card, terrain, interaction, GetCurrentTotalTime());
    }

    private void CancelReusableGatheringHold()
    {
        if (_holdingCard != null && IsInstanceValid(_holdingCard))
        {
            _holdingCard.CancelHoldProgress();
        }

        _holdingCard = null;
        _holdingEffectiveTimeCost = 0;
    }

    private static bool TryGetReusableGathering(
        BoardCardView card,
        out TerrainInstance terrain,
        out ReusableGatheringInteraction interaction)
    {
        terrain = card?.GetTerrainInstanceOrNull();
        interaction = terrain?.TerrainData?.InteractionBehavior as ReusableGatheringInteraction;
        return terrain != null && interaction != null;
    }

    private static void RefreshReusableGatheringCard(
        BoardCardView card,
        TerrainInstance terrain,
        ReusableGatheringInteraction interaction,
        int totalTimePassed)
    {
        bool canHarvest = interaction.CanHarvest(terrain, totalTimePassed);
        card.SetInteractionDisabled(!canHarvest);
    }

    private static int GetCurrentTotalTime()
    {
        return TimeSystem.Instance?.TotalTimePassed ?? 0;
    }
}
