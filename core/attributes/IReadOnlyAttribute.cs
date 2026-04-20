namespace CUSGA.core.attributes;

public interface IReadOnlyAttribute
{
    AttributeType Type { get; }
    string DisplayName { get; }

    float BaseValue { get; }
    float BonusValue { get; }
    int AllocatedPoints { get; }
    float GrowthPerPoint { get; }

    float RawValue { get; }
}
