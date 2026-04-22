using System;
using Godot;
using Godot.Collections;
using CUSGA.resources.encounters;

namespace CUSGA.core.autoloads;

public partial class EncounterManager : Node
{
    public static EncounterManager Instance { get; private set; } = null!;

    [Export] public Array<GatheringEncounterRule> GatheringRules { get; set; } = [];

    [Export] public float BaseGatheringSpawnChance { get; set; } = 0.05f;
    [Export] public float NightChanceMultiplier { get; set; } = 6.0f;

    public override void _Ready()
    {
        Instance = this;
    }

    public GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag)
    {
        if (resourceTag.IsEmpty)
        {
            return GatheringEncounterResult.None();
        }

        float timeModifier = TimeSystem.Instance.IsNight ? NightChanceMultiplier : 1.0f;

        foreach (var rule in GatheringRules)
        {
            if (rule == null)
            {
                continue;
            }

            if (rule.TriggerTag != resourceTag)
            {
                continue;
            }

            float finalChance = BaseGatheringSpawnChance * timeModifier * Mathf.Max(rule.ExtraChanceMultiplier, 0.0f);

            if (GD.Randf() <= finalChance)
            {
                if (rule.MonsterToSpawn == null)
                {
                    return GatheringEncounterResult.None();
                }

                return GatheringEncounterResult.Create(
                    rule.MonsterToSpawn,
                    rule.SpawnMessage
                );
            }
        }

        return GatheringEncounterResult.None();
    }
}
