using CUSGA.resources.monsters;
using Godot;
using System;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class FactionComponent : Node
{
    [Export] public MonsterFaction Faction { get; set; }
}
