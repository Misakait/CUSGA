using Godot;
using Godot.Collections;

namespace CUSGA.resources.monster;

[GlobalClass]
public partial class MonsterSkillSetData : Resource
{
    [Export] public Array<MonsterSkillEntryData> Skills { get; set; } = [];
}
