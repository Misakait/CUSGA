using CUSGA.resources.monsters;
using Godot;
using Godot.Collections;

namespace CUSGA.resources.map;

/// <summary>
/// 表示一次通道驻守战斗会生成的怪物组合。
/// </summary>
[GlobalClass]
public partial class PassageGuardEncounterData : Resource
{
    /// <summary>
    /// 本次 encounter 的怪物数组；可以是一只或多只怪物。
    /// </summary>
    [Export] public Array<MonsterData> Monsters { get; set; } = [];
}
