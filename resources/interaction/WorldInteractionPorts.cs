using Godot;
using Godot.Collections;
using CUSGA.core.inventory;
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
    void SpawnLootCards(Array<ItemStack> drops, Vector2 spawnOrigin);
    void RemoveSourceCard();
}

public interface IInteractionEncounterPort
{
    GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag);
}
