namespace CUSGA.resources.encounters;

public sealed class MonsterStatMultiplier
{
    public static MonsterStatMultiplier Identity => new()
    {
        MaxHealth = 1f,
        PhysAtk = 1f,
        PhysDef = 1f,
        MagPower = 1f,
        MagResist = 1f,
        Speed = 1f
    };

    public float MaxHealth { get; set; } = 1f;
    public float PhysAtk { get; set; } = 1f;
    public float PhysDef { get; set; } = 1f;
    public float MagPower { get; set; } = 1f;
    public float MagResist { get; set; } = 1f;
    public float Speed { get; set; } = 1f;
}
