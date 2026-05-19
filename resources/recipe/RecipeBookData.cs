using Godot;
using Godot.Collections;

namespace CUSGA.resources.crafting;

[GlobalClass]
public partial class RecipeBookData : Resource
{
    [Export] public Array<CraftingRecipe> Recipes { get; set; } = [];
}
