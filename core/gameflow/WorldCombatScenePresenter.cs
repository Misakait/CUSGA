using System.Threading.Tasks;
using Godot;
using Godot.Collections;
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
    private const string MapBackgroundResolverScriptPath =
        "res://core/gameflow/current_map_background_resolver.gd";

    private bool _isTransitioning;

    public async Task EnterCombatAsync(Array<Resource> battleDeck, Array<MonsterData> monsters)
    {
        await EnterCombatAsync(battleDeck, monsters, null);
    }

    /// <summary>
    /// 进入战斗并等待战斗结果。
    /// </summary>
    /// <param name="battleDeck">玩家本场战斗使用的技能卡组。</param>
    /// <param name="monsters">本场战斗生成的怪物数组。</param>
    /// <returns>战斗胜利时返回 true；无法进入战斗或失败时返回 false。</returns>
    public async Task<bool> EnterCombatAndWaitForResultAsync(
        Array<Resource> battleDeck,
        Array<MonsterData> monsters)
    {
        if (_isTransitioning)
        {
            return false;
        }

        var completion = new TaskCompletionSource<bool>();
        await EnterCombatAsync(battleDeck, monsters, completion);
        return await completion.Task;
    }

    private async Task EnterCombatAsync(
        Array<Resource> battleDeck,
        Array<MonsterData> monsters,
        TaskCompletionSource<bool> completion)
    {
        if (_isTransitioning)
        {
            completion?.TrySetResult(false);
            return;
        }

        _isTransitioning = true;
        GD.Print("[WorldCombatScenePresenter] Entering Combat!");
        try
        {
            await screenTransitions.FadeOutAsync();

            Node battleInstance = CreateBattleInstance(battleDeck, monsters);
            Sprite2D battleBackground = DuplicateCurrentBackground(mapSystem);
            if (battleBackground != null)
            {
                battleInstance.AddChild(battleBackground);
            }

            battleInstance.Connect(
                BattleEndedSignal,
                Callable.From<bool>(isVictory => OnBattleEnded(battleInstance, isVictory, completion))
            );

            worldRoot.AddChild(battleInstance);
            worldView.HideWorldView();

            await screenTransitions.FadeInAsync();
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    private async void OnBattleEnded(Node battleInstance, bool isVictory, TaskCompletionSource<bool> completion)
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
            completion?.TrySetResult(isVictory);
        }
        finally
        {
            _isTransitioning = false;
        }
    }

    private static Node CreateBattleInstance(Array<Resource> battleDeck, Array<MonsterData> monsters)
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

    /// <summary>
    /// 通过稳定方法协议调用生产 GDScript 背景解析器。
    /// </summary>
    /// <param name="mapSystem">包含 MapInstantiator 的地图系统节点。</param>
    /// <returns>复制出的战斗背景；脚本或协议不可用时返回 null。</returns>
    private static Sprite2D DuplicateCurrentBackground(Node mapSystem)
    {
        Script resolverScript = GD.Load<Script>(MapBackgroundResolverScriptPath);
        if (resolverScript == null)
        {
            GD.PushError($"无法加载战斗背景解析器：{MapBackgroundResolverScriptPath}");
            return null;
        }

        Variant resolverValue = resolverScript.Call("new");
        if (resolverValue.AsGodotObject() is not RefCounted resolver
            || !resolver.HasMethod("DuplicateCurrentBackground"))
        {
            GD.PushError("战斗背景解析器缺少 DuplicateCurrentBackground 协议。");
            return null;
        }

        return resolver.Call("DuplicateCurrentBackground", mapSystem).AsGodotObject() as Sprite2D;
    }

}
