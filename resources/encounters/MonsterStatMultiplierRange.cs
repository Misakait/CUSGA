using Godot;

namespace CUSGA.resources.encounters;

[GlobalClass]
public partial class MonsterStatMultiplierRange : Resource
{
    [ExportGroup("Min")]
    [Export] public float MinMaxHealth { get; set; } = 1f;
    [Export] public float MinPhysAtk { get; set; } = 1f;
    [Export] public float MinPhysDef { get; set; } = 1f;
    [Export] public float MinMagPower { get; set; } = 1f;
    [Export] public float MinMagResist { get; set; } = 1f;
    [Export] public float MinSpeed { get; set; } = 1f;

    [ExportGroup("Max")]
    [Export] public float MaxMaxHealth { get; set; } = 1f;
    [Export] public float MaxPhysAtk { get; set; } = 1f;
    [Export] public float MaxPhysDef { get; set; } = 1f;
    [Export] public float MaxMagPower { get; set; } = 1f;
    [Export] public float MaxMagResist { get; set; } = 1f;
    [Export] public float MaxSpeed { get; set; } = 1f;

    public MonsterStatMultiplier Min
    {
        get => new()
        {
            MaxHealth = MinMaxHealth,
            PhysAtk = MinPhysAtk,
            PhysDef = MinPhysDef,
            MagPower = MinMagPower,
            MagResist = MinMagResist,
            Speed = MinSpeed
        };
        set
        {
            value ??= MonsterStatMultiplier.Identity;
            MinMaxHealth = value.MaxHealth;
            MinPhysAtk = value.PhysAtk;
            MinPhysDef = value.PhysDef;
            MinMagPower = value.MagPower;
            MinMagResist = value.MagResist;
            MinSpeed = value.Speed;
        }
    }

    public MonsterStatMultiplier Max
    {
        get => new()
        {
            MaxHealth = MaxMaxHealth,
            PhysAtk = MaxPhysAtk,
            PhysDef = MaxPhysDef,
            MagPower = MaxMagPower,
            MagResist = MaxMagResist,
            Speed = MaxSpeed
        };
        set
        {
            value ??= MonsterStatMultiplier.Identity;
            MaxMaxHealth = value.MaxHealth;
            MaxPhysAtk = value.PhysAtk;
            MaxPhysDef = value.PhysDef;
            MaxMagPower = value.MagPower;
            MaxMagResist = value.MagResist;
            MaxSpeed = value.Speed;
        }
    }
}
