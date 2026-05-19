using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.core.application;
using CUSGA.resources.interaction.operations;
using CUSGA.resources.item.card;
using CUSGA.resources.monsters;
using Godot.Collections;

namespace CUSGA.core.gameplay;

public partial class WorldInteractionCoordinator : Node
{
    [Export] public NodePath BoardControllerPath { get; set; } = null!;
    [Export] public NodePath GameplayPortPath { get; set; } = null!;
    [Export] public NodePath BackpackFlyTargetPath { get; set; } = null!;
    [Export] public NodePath EncounterManagerPath { get; set; } = null!;
    [Export] public NodePath ScreenTransitionsPath { get; set; } = new("/root/ScreenTransitions");

    private EncounterManager _encounterManager;
    private BoardController _boardController = null!;
    private GameplayPort _gameplayPort = null!;
    private Control _backpackFlyTarget;
    private Node _globalEventBus;
    private Node _screenTransitions;
    private bool _isTransitioning;

    public override void _Ready()
    {
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _backpackFlyTarget = GetNodeOrNull<Control>(BackpackFlyTargetPath);
        _globalEventBus = GetNodeOrNull<Node>("/root/GlobalEventBus");
        _encounterManager = GetNode<EncounterManager>(EncounterManagerPath);
        _screenTransitions = GetNodeOrNull<Node>(ScreenTransitionsPath);

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
        if (_isTransitioning)
        {
            return;
        }

        _isTransitioning = true;
        GD.Print($"[WorldInteractionCoordinator] Entering Combat!");
        try
        {
            await FadeOutAsync();

            PackedScene battleScene = GD.Load<PackedScene>("res://scenes/battle_scenes/battle.tscn");
            Node battleInstance = battleScene.Instantiate();

            // 传递由 GameplayPort 获取到的玩家战斗卡组和遭遇到的怪物数据，给即将生成的战斗场景
            if (battleDeck != null && battleDeck.Count > 0)
            {
                battleInstance.Set("starting_deck_data", battleDeck);
            }
            if (monsters != null && monsters.Count > 0)
            {
                battleInstance.Set("starting_monster_data", monsters);
            }

            // 将当前地图背景克隆到战斗场景中，作为战斗背景
            Sprite2D battleBackground = TryDuplicateCurrentMapBackground();
            if (battleBackground != null)
            {
                battleInstance.AddChild(battleBackground);
            }

            // 监听战斗结束信号，用于在战斗完成后销毁战斗场景并恢复主界面
            battleInstance.Connect("battle_ended", Callable.From<bool>(isVictory => OnBattleEnded(battleInstance, isVictory)));

            // 将战斗场景添加为主场景的子节点，从而将其加入游戏渲染树
            GetNode("/root/Main").AddChild(battleInstance);

            // 隐藏主界面的各个模块（棋盘、地图、背包UI等），确保战斗画面不受遮挡
            GetNode<CanvasItem>("/root/Main/BoardSystem/BoardController").Hide();
            GetNode<CanvasItem>("/root/Main/MapSystem").Hide();
            // 小地图因为在 CanvasLayer 下，需要单独隐藏
            GetNode<CanvasLayer>("/root/Main/MapSystem/CanvasLayer").Hide();
            GetNode<CanvasLayer>("/root/Main/UI/HUDLayer").Hide();

            await FadeInAsync();
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    /// <summary>
    /// 处理战斗结束的逻辑
    /// </summary>
    /// <param name="battleInstance">当前的战斗场景实例</param>
    /// <param name="isVictory">战斗是否胜利</param>
    private async void OnBattleEnded(Node battleInstance, bool isVictory)
    {
        if (_isTransitioning)
        {
            return;
        }

        _isTransitioning = true;
        GD.Print($"[WorldInteractionCoordinator] Combat Ended! Victory: {isVictory}");
        try
        {
            await FadeOutAsync();

            // 销毁战斗场景
            if (IsInstanceValid(battleInstance))
            {
                battleInstance.QueueFree();
            }
            // TODO：隐藏/显示主世界 UI”抽成一个 `WorldViewVisibilityController
            // 重新显示主场景界面的各系统和小地图
            GetNode<CanvasItem>("/root/Main/BoardSystem/BoardController").Show();
            GetNode<CanvasItem>("/root/Main/MapSystem").Show();
            GetNode<CanvasLayer>("/root/Main/MapSystem/CanvasLayer").Show();
            GetNode<CanvasLayer>("/root/Main/UI/HUDLayer").Show();

            await FadeInAsync();
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    private async Task FadeOutAsync()
    {
        await RunScreenTransitionAsync("fade_out", "fade_complete");
    }

    private async Task FadeInAsync()
    {
        await RunScreenTransitionAsync("fade_in", "fade_in_complete");
    }

    private async Task RunScreenTransitionAsync(string methodName, string completedSignal)
    {
        if (_screenTransitions == null || !_screenTransitions.HasMethod(methodName))
        {
            return;
        }

        _screenTransitions.Call(methodName);
        await ToSignal(_screenTransitions, completedSignal);
    }

    private Sprite2D TryDuplicateCurrentMapBackground()
    {
        Node mapSystem = GetNodeOrNull<Node>("/root/Main/MapSystem");
        if (mapSystem == null)
        {
            return null;
        }

        Node mapInstantiator = mapSystem.GetNodeOrNull<Node>("MapInstantiator");
        if (mapInstantiator == null)
        {
            return null;
        }

        foreach (Node child in mapInstantiator.GetChildren())
        {
            if (child is not Node2D roomScene)
            {
                continue;
            }

            Sprite2D background = roomScene.GetNodeOrNull<Sprite2D>("Background");
            if (background == null)
            {
                continue;
            }

            if (background.Duplicate() is not Sprite2D duplicated)
            {
                return null;
            }

            duplicated.Name = "MapBackground";
            duplicated.ZIndex = -100;
            duplicated.ZAsRelative = false;
            return duplicated;
        }

        return null;
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
