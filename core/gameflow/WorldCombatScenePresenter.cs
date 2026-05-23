using System.Threading.Tasks;
using Godot;
using Godot.Collections;
using CUSGA.resources.item.card;
using CUSGA.resources.monsters;

namespace CUSGA.core.gameflow;

public sealed class WorldCombatScenePresenter(
    Node worldRoot,
    Node mapSystem,
    ScreenTransitionAdapter screenTransitions,
    WorldViewVisibilityController worldView)
{
    private const string BattleEndedSignal = "battle_ended";
    private const string BattleScenePath = "res://scenes/battle_scenes/battle.tscn";

    private bool _isTransitioning;

    public async Task EnterCombatAsync(Array<SkillCardData> battleDeck, Array<MonsterData> monsters)
    {
        if (_isTransitioning)
        {
            return;
        }

        _isTransitioning = true;
        GD.Print("[WorldCombatScenePresenter] Entering Combat!");
        try
        {
            await screenTransitions.FadeOutAsync();

            Node battleInstance = CreateBattleInstance(battleDeck, monsters);
            Sprite2D battleBackground = TryDuplicateCurrentMapBackground();
            if (battleBackground != null)
            {
                battleInstance.AddChild(battleBackground);
            }

            battleInstance.Connect(BattleEndedSignal, Callable.From<bool>(
                isVictory => OnBattleEnded(battleInstance, isVictory)
            ));

            worldRoot.AddChild(battleInstance);
            worldView.HideWorldView();

            await screenTransitions.FadeInAsync();
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    private async void OnBattleEnded(Node battleInstance, bool isVictory)
    {
        if (_isTransitioning)
        {
            return;
        }

        _isTransitioning = true;
        GD.Print($"[WorldCombatScenePresenter] Combat Ended! Victory: {isVictory}");
        try
        {
            await screenTransitions.FadeOutAsync();

            if (GodotObject.IsInstanceValid(battleInstance))
            {
                battleInstance.QueueFree();
            }

            worldView.ShowWorldView();

            await screenTransitions.FadeInAsync();
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    private static Node CreateBattleInstance(Array<SkillCardData> battleDeck, Array<MonsterData> monsters)
    {
        PackedScene battleScene = GD.Load<PackedScene>(BattleScenePath);
        Node battleInstance = battleScene.Instantiate();

        if (battleDeck != null && battleDeck.Count > 0)
        {
            battleInstance.Set("starting_deck_data", battleDeck);
        }
        if (monsters != null && monsters.Count > 0)
        {
            battleInstance.Set("starting_monster_data", monsters);
        }

        return battleInstance;
    }

    private Sprite2D TryDuplicateCurrentMapBackground()
    {
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
}
