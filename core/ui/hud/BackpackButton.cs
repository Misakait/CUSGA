using Godot;
using CUSGA.entities.components;
using CUSGA.core.constants;
using System.Collections.Generic;
using CUSGA.resources.item;
using CUSGA.core.application;

namespace CUSGA.core.ui.hud;

public partial class BackpackButton : Button
{
    [Export]
    public NodePath GameplayPortPath;
    private GameplayPort _gameplayPort;
    public override void _Ready()
    {
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
    }

    public override void _Pressed()
    {
        _gameplayPort.RequestToggleInventory();
    }
}
