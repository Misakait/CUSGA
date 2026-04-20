using Godot;

namespace CUSGA.resources.item;

[GlobalClass]
public abstract partial class BaseCardData : Resource
{
    [Export] public StringName CardId { get; set; }
    [Export] public string CardName { get; set; }
    [Export] public Texture2D CardIcon { get; set; }
    [Export(PropertyHint.MultilineText)] public string Description { get; set; }
}
