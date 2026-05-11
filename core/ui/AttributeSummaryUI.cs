using Godot;
using CUSGA.core.attributes;
using CUSGA.entities.components;

namespace CUSGA.core.ui;

public partial class AttributeSummaryUI : PanelContainer
{
    private AttributeComponent _attributes;

    private Label _physAtkValue = null!;
    private Label _physDefValue = null!;
    private Label _magPowerValue = null!;
    private Label _magResistValue = null!;
    private Label _speedValue = null!;
    private Label _physBoostValue = null!;
    private Label _magicBoostValue = null!;

    public override void _Ready()
    {
        _physAtkValue = GetNode<Label>("%PhysAtkValue");
        _physDefValue = GetNode<Label>("%PhysDefValue");
        _magPowerValue = GetNode<Label>("%MagPowerValue");
        _magResistValue = GetNode<Label>("%MagResistValue");
        _speedValue = GetNode<Label>("%SpeedValue");
        _physBoostValue = GetNode<Label>("%PhysBoostValue");
        _magicBoostValue = GetNode<Label>("%MagicBoostValue");
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
        SetPercentValue(_physBoostValue, AttributeType.PhysDamageBoost);
        SetPercentValue(_magicBoostValue, AttributeType.MagicDamageBoost);
    }

    private void SetValue(Label label, AttributeType type)
    {
        label.Text = _attributes == null
            ? "-"
            : FormatNumber(_attributes.GetEffectiveValue(type));
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
