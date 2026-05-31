using Godot;
using CUSGA.core.attributes;
using CUSGA.entities.components;

namespace CUSGA.core.ui;

/// <summary>
/// 显示角色基础五维属性，并通过详情弹窗展示完整战斗属性。
/// </summary>
public partial class AttributeSummaryUI : PanelContainer
{
    private AttributeComponent _attributes;

    private Label _physAtkValue = null!;
    private Label _physDefValue = null!;
    private Label _magPowerValue = null!;
    private Label _magResistValue = null!;
    private Label _speedValue = null!;
    private Button _detailsButton = null!;
    private PopupPanel _detailsPopup = null!;
    private Label _maxHealthDetailValue = null!;
    private Label _maxEnergyDetailValue = null!;
    private Label _physPenetrationDetailValue = null!;
    private Label _magicPenetrationDetailValue = null!;
    private Label _critRateDetailValue = null!;
    private Label _critDamageDetailValue = null!;
    private Label _evasionRateDetailValue = null!;
    private Label _lifestealRateDetailValue = null!;

    public override void _Ready()
    {
        _physAtkValue = GetNode<Label>("%PhysAtkValue");
        _physDefValue = GetNode<Label>("%PhysDefValue");
        _magPowerValue = GetNode<Label>("%MagPowerValue");
        _magResistValue = GetNode<Label>("%MagResistValue");
        _speedValue = GetNode<Label>("%SpeedValue");
        _detailsButton = GetNode<Button>("%DetailsButton");
        _detailsPopup = GetNode<PopupPanel>("%AttributeDetailsPopup");
        _maxHealthDetailValue = GetNode<Label>("%MaxHealthDetailValue");
        _maxEnergyDetailValue = GetNode<Label>("%MaxEnergyDetailValue");
        _physPenetrationDetailValue = GetNode<Label>("%PhysPenetrationDetailValue");
        _magicPenetrationDetailValue = GetNode<Label>("%MagicPenetrationDetailValue");
        _critRateDetailValue = GetNode<Label>("%CritRateDetailValue");
        _critDamageDetailValue = GetNode<Label>("%CritDamageDetailValue");
        _evasionRateDetailValue = GetNode<Label>("%EvasionRateDetailValue");
        _lifestealRateDetailValue = GetNode<Label>("%LifestealRateDetailValue");
        _detailsButton.Pressed += OnDetailsButtonPressed;
        Refresh();
    }

    public void Bind(AttributeComponent attributes)
    {
        if (_attributes == attributes)
        {
            Refresh();
            return;
        }

        DisconnectAttributeSignals();
        _attributes = attributes;

        if (_attributes != null)
        {
            _attributes.AttributeChanged += OnAttributeChanged;
            _attributes.AvailablePointsChanged += OnAvailablePointsChanged;
        }

        Refresh();
    }

    public override void _ExitTree()
    {
        if (_detailsButton != null)
        {
            _detailsButton.Pressed -= OnDetailsButtonPressed;
        }

        DisconnectAttributeSignals();
    }

    private void DisconnectAttributeSignals()
    {
        if (_attributes == null)
        {
            return;
        }

        _attributes.AttributeChanged -= OnAttributeChanged;
        _attributes.AvailablePointsChanged -= OnAvailablePointsChanged;
    }

    private void OnAttributeChanged(AttributeChangedEvent changeEvent)
    {
        Refresh();
    }

    private void OnAvailablePointsChanged(int availablePoints)
    {
        Refresh();
    }

    private void Refresh()
    {
        if (!IsNodeReady())
        {
            return;
        }

        SetValue(_physAtkValue, AttributeType.PhysAtk);
        SetValue(_physDefValue, AttributeType.PhysDef);
        SetValue(_magPowerValue, AttributeType.MagPower);
        SetValue(_magResistValue, AttributeType.MagResist);
        SetValue(_speedValue, AttributeType.Speed);
        RefreshDetails();
    }

    private void OnDetailsButtonPressed()
    {
        RefreshDetails();
        _detailsPopup.PopupCentered();
    }

    private void RefreshDetails()
    {
        SetValue(_maxHealthDetailValue, AttributeType.MaxHealth);
        SetValue(_maxEnergyDetailValue, AttributeType.MaxEnergy);
        SetPenetrationValue(
            _physPenetrationDetailValue,
            AttributeType.FixedPhysPenetration,
            AttributeType.PhysPenetrationRate
        );
        SetPenetrationValue(
            _magicPenetrationDetailValue,
            AttributeType.FixedMagicPenetration,
            AttributeType.MagicPenetrationRate
        );
        SetPercentValue(_critRateDetailValue, AttributeType.CritRate);
        SetPercentValue(_critDamageDetailValue, AttributeType.CritDamage);
        SetPercentValue(_evasionRateDetailValue, AttributeType.EvasionRate);
        SetPercentValue(_lifestealRateDetailValue, AttributeType.LifestealRate);
    }

    private void SetValue(Label label, AttributeType type)
    {
        label.Text = _attributes == null
            ? "-"
            : FormatNumber(_attributes.GetEffectiveValue(type));
    }

    private void SetPenetrationValue(Label label, AttributeType fixedType, AttributeType rateType)
    {
        label.Text = _attributes == null
            ? "-"
            : $"{FormatNumber(_attributes.GetEffectiveValue(fixedType))} | {_attributes.GetEffectiveValue(rateType) * 100f:0.#}%";
    }

    private void SetPercentValue(Label label, AttributeType type)
    {
        label.Text = _attributes == null
            ? "-"
            : $"{_attributes.GetEffectiveValue(type) * 100f:0.#}%";
    }

    private static string FormatNumber(float value)
    {
        return Mathf.IsEqualApprox(value, Mathf.Round(value))
            ? Mathf.RoundToInt(value).ToString()
            : $"{value:0.#}";
    }
}
