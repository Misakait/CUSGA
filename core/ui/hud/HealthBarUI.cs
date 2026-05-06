using System;
using Godot;
using CUSGA.core.application;
using CUSGA.entities.components;

namespace CUSGA.core.ui.hud;

public partial class HealthBarUI : Control
{
    [Export] public NodePath GameplayPortPath { get; set; }

    private GameplayPort _gameplayPort = null!;
    private HealthComponent _health = null!;

    private ProgressBar _healthBar = null!;
    private Label _healthLabel = null!;

    public override void _Ready()
    {
        if (GameplayPortPath.IsEmpty)
        {
            throw new InvalidOperationException("HealthBarUI.GameplayPortPath 未设置");
        }

        _healthBar = GetNode<ProgressBar>("%HealthBar");
        _healthLabel = GetNode<Label>("%HealthLabel");

        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        Bind(_gameplayPort.PlayerHealth);
    }

    public override void _ExitTree()
    {
        Unbind();
    }

    public void Bind(HealthComponent health)
    {
        ArgumentNullException.ThrowIfNull(health);

        if (_health == health)
        {
            return;
        }

        Unbind();

        _health = health;
        _health.ValueChanged += OnHealthChanged;

        Refresh(_health.CurrentValue, _health.MaxValue);
    }

    private void Unbind()
    {
        if (_health == null)
        {
            return;
        }

        _health.ValueChanged -= OnHealthChanged;
        _health = null!;
    }

    private void OnHealthChanged(int currentValue, int maxValue)
    {
        Refresh(currentValue, maxValue);
    }

    private void Refresh(int currentValue, int maxValue)
    {
        _healthBar.MaxValue = maxValue;
        _healthBar.Value = currentValue;
        _healthLabel.Text = $"{currentValue} / {maxValue}";
    }
}
