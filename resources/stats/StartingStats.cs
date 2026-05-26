using Godot;
namespace CUSGA.resources.stats;

/// <summary>
/// 角色或怪物进入战斗时使用的五维初始属性配置。
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
}
