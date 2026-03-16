using Godot;

namespace CUSGA.resources.talents;

[GlobalClass]
public partial class TalentData : Resource
{
    [Export] public string TalentName { get; set; }
    [Export(PropertyHint.MultilineText)] public string Description { get; set; }
    [Export] public Texture2D TalentTexture { get; set; }
}
