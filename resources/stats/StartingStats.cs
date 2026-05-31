using Godot;
namespace CUSGA.resources.stats;

/// <summary>
/// 角色或怪物进入战斗时使用的战斗初始属性配置。
/// </summary>
/// <remarks>
/// 五维默认参考值统一为 100；旧数值体系中物攻、法强以 10 为基准，物抗、法抗以 5 为基准，速度已经以 100 为基准。
/// 因此这里的默认值和成长值按对应比例放大，便于策划在同一数值尺度下配置所有战斗属性。
/// </remarks>
[GlobalClass]
public partial class StartingStats : Resource
{
    /// <summary>
    /// 获取或设置基础物理攻击。
    /// </summary>
    [Export] public float BasePhysAtk { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级物理攻击成长值。
    /// </summary>
    [Export] public float PhysAtkGrowth { get; set; } = 25f;

    /// <summary>
    /// 获取或设置基础物理抗性。
    /// </summary>
    [Export] public float BasePhysDef { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级物理抗性成长值。
    /// </summary>
    [Export] public float PhysDefGrowth { get; set; } = 20f;

    /// <summary>
    /// 获取或设置基础法术强度。
    /// </summary>
    [Export] public float BaseMagPower { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级法术强度成长值。
    /// </summary>
    [Export] public float MagPowerGrowth { get; set; } = 30f;

    /// <summary>
    /// 获取或设置基础法术抗性。
    /// </summary>
    [Export] public float BaseMagResist { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级法术抗性成长值。
    /// </summary>
    [Export] public float MagResistGrowth { get; set; } = 20f;

    /// <summary>
    /// 获取或设置基础速度。
    /// </summary>
    [Export] public float BaseSpeed { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级速度成长值。
    /// </summary>
    [Export] public float SpeedGrowth { get; set; } = 5f;

    /// <summary>
    /// 获取或设置基础生命上限。
    /// </summary>
    [Export] public float BaseMaxHealth { get; set; } = 1000f;

    /// <summary>
    /// 获取或设置每级生命上限成长值。
    /// </summary>
    [Export] public float MaxHealthGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础能量上限。
    /// </summary>
    [Export] public float BaseMaxEnergy { get; set; } = 100f;

    /// <summary>
    /// 获取或设置每级能量上限成长值。
    /// </summary>
    [Export] public float MaxEnergyGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础固定物理穿透。
    /// </summary>
    [Export] public float BaseFixedPhysPenetration { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级固定物理穿透成长值。
    /// </summary>
    [Export] public float FixedPhysPenetrationGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础物理穿透率。
    /// </summary>
    [Export] public float BasePhysPenetrationRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级物理穿透率成长值。
    /// </summary>
    [Export] public float PhysPenetrationRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础固定法术穿透。
    /// </summary>
    [Export] public float BaseFixedMagicPenetration { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级固定法术穿透成长值。
    /// </summary>
    [Export] public float FixedMagicPenetrationGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础法术穿透率。
    /// </summary>
    [Export] public float BaseMagicPenetrationRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级法术穿透率成长值。
    /// </summary>
    [Export] public float MagicPenetrationRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础暴击率。
    /// </summary>
    [Export] public float BaseCritRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级暴击率成长值。
    /// </summary>
    [Export] public float CritRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础暴击伤害倍率。
    /// </summary>
    [Export] public float BaseCritDamage { get; set; } = 1.5f;

    /// <summary>
    /// 获取或设置每级暴击伤害倍率成长值。
    /// </summary>
    [Export] public float CritDamageGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础闪避率。
    /// </summary>
    [Export] public float BaseEvasionRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级闪避率成长值。
    /// </summary>
    [Export] public float EvasionRateGrowth { get; set; } = 0f;

    /// <summary>
    /// 获取或设置基础吸血率。
    /// </summary>
    [Export] public float BaseLifestealRate { get; set; } = 0f;

    /// <summary>
    /// 获取或设置每级吸血率成长值。
    /// </summary>
    [Export] public float LifestealRateGrowth { get; set; } = 0f;
}
