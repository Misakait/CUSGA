using Godot;
using CUSGA.resources.monsters;
using System;
using Godot.Collections;

namespace CUSGA.resources.encounters;

public partial class GatheringEncounterResult : RefCounted
{
    public bool Triggered { get; set; } = false;

    public Array<MonsterData> MonsterToSpawn { get; set; }

    public string SpawnMessage { get; set; } = string.Empty;

    public static GatheringEncounterResult None()
    {
        return new GatheringEncounterResult
        {
            Triggered = false
        };
    }

    public static GatheringEncounterResult Create(Array<MonsterData> monster, string message)
    {
        return new GatheringEncounterResult
        {
            Triggered = true,
            MonsterToSpawn = monster,
            SpawnMessage = message ?? string.Empty
        };
    }
}
