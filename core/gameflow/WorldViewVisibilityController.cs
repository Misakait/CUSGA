using Godot;

namespace CUSGA.core.gameflow;

public sealed class WorldViewVisibilityController(
    Node root,
    NodePath boardControllerPath,
    NodePath mapSystemPath,
    NodePath mapCanvasLayerPath,
    NodePath hudLayerPath)
{
    public void HideWorldView()
    {
        SetWorldViewVisible(false);
    }

    public void ShowWorldView()
    {
        SetWorldViewVisible(true);
    }

    private void SetWorldViewVisible(bool visible)
    {
        SetCanvasItemVisible(boardControllerPath, visible);
        SetCanvasItemVisible(mapSystemPath, visible);
        SetCanvasLayerVisible(mapCanvasLayerPath, visible);
        SetCanvasLayerVisible(hudLayerPath, visible);
    }

    private void SetCanvasItemVisible(NodePath path, bool visible)
    {
        CanvasItem node = root.GetNode<CanvasItem>(path);
        SetVisible(node, visible);
    }

    private void SetCanvasLayerVisible(NodePath path, bool visible)
    {
        CanvasLayer node = root.GetNode<CanvasLayer>(path);
        SetVisible(node, visible);
    }

    private static void SetVisible(CanvasItem node, bool visible)
    {
        if (visible)
        {
            node.Show();
        }
        else
        {
            node.Hide();
        }
    }

    private static void SetVisible(CanvasLayer node, bool visible)
    {
        if (visible)
        {
            node.Show();
        }
        else
        {
            node.Hide();
        }
    }
}
