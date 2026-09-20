using Godot;
using Godot.Collections;
using CUSGA.resources.encounters;
using CUSGA.resources.monsters;

namespace CUSGA.resources.interaction;

public interface IInteractionGameplayPort
{
    void RequestOpenFarmingPanel(TerrainInstance terrain);
    void RequestOpenWarehouse();
    void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message);
    void RequestEncounter(TerrainInstance terrain, Array<MonsterData> monsters, string message);
}

public interface IInteractionBoardPort
{
    /// <summary>
    /// 生成旧 C# 或 GDScript ItemStack 对应的棋盘掉落卡。
    /// </summary>
    /// <param name="drops">由跨语言 RefCounted 堆叠组成的非泛型数组。</param>
    /// <param name="spawnOrigin">掉落卡散射动画的全局起点。</param>
    void SpawnLootCards(Array drops, Vector2 spawnOrigin);
    void RemoveSourceCard();
}

public interface IInteractionEncounterPort
{
    GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag);
}
