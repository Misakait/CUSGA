using System;
using Godot;
using CUSGA.core.application;

namespace CUSGA.core.ui.hud;

public partial class HUDController : Control
{
    [Export] public NodePath GameplayPortPath { get; set; }
    [Export] public NodePath BackpackButtonPath { get; set; }

    private GameplayPort _gameplayPort = null!;
    private BaseButton _backpackButton = null!;

    public override void _Ready()
    {
        if (GameplayPortPath.IsEmpty)
        {
            throw new InvalidOperationException("HUDController.GameplayPortPath 未设置");
        }

        if (BackpackButtonPath.IsEmpty)
        {
            throw new InvalidOperationException("HUDController.BackpackButtonPath 未设置");
        }

        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _backpackButton = GetNode<BaseButton>(BackpackButtonPath);

        // _backpackButton.Pressed += OnBackpackButtonPressed;
    }

    public override void _ExitTree()
    {
        // if (_backpackButton != null)
        //     _backpackButton.Pressed -= OnBackpackButtonPressed;
    }

    public override void _Input(InputEvent @event)
    {
        if (IsActionPressedOnce(@event, "toggle_crafting"))
        {
            _gameplayPort.RequestToggleCrafting();
            GetViewport().SetInputAsHandled();
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed("toggle_inventory"))
        {
            _gameplayPort.RequestToggleInventory();
            GetViewport().SetInputAsHandled();
        }
    }

    private static bool IsActionPressedOnce(InputEvent @event, string action)
    {
        if (!@event.IsActionPressed(action))
        {
            return false;
        }

        return @event is not InputEventKey keyEvent || !keyEvent.Echo;
    }

    // private void OnBackpackButtonPressed()
    // {
    //     _gameplayPort.RequestToggleInventory();
    // }
}
