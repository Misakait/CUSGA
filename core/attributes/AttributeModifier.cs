using Godot;

namespace CUSGA.core.attributes;

public enum AttributeModifierMode
{
    FlatAdd,
    PercentAdd,
    PercentMul
}

public readonly record struct AttributeModifier(
    AttributeType Type,
    AttributeModifierMode Mode,
    float ValuePerStack,
    int Stacks,
    StringName SourceId
);
