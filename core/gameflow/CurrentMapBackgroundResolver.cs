using Godot;

namespace CUSGA.core.gameflow;

/// <summary>
/// 从地图系统中解析当前房间背景，并复制给战斗场景使用。
/// </summary>
[GlobalClass]
public partial class CurrentMapBackgroundResolver : RefCounted
{
    /// <summary>
    /// 复制当前地图房间的背景节点。
    /// </summary>
    /// <param name="mapSystem">包含 MapInstantiator 子节点的地图系统节点。</param>
    /// <returns>成功时返回复制出的背景 Sprite2D；没有可用背景时返回 null。</returns>
    public static Sprite2D DuplicateCurrentBackground(Node mapSystem)
    {
        Sprite2D background = FindCurrentBackground(mapSystem);
        if (background == null)
        {
            return null;
        }

        if (background.Duplicate() is not Sprite2D duplicated)
        {
            return null;
        }
        GD.Print("成功复制场景背景");
        duplicated.Name = "MapBackground";
        duplicated.ZIndex = -1;
        duplicated.ZAsRelative = false;
        return duplicated;
    }

    private static Sprite2D FindCurrentBackground(Node mapSystem)
    {
        if (mapSystem == null)
        {
            return null;
        }

        Node mapInstantiator = mapSystem.GetNodeOrNull<Node>("MapInstantiator");
        if (mapInstantiator == null)
        {
            return null;
        }

        // MapInstantiator 会缓存房间实例，子节点顺序不一定代表玩家当前所在房间。
        Sprite2D currentBackground = TryGetBackground(TryGetCurrentScene(mapInstantiator));
        if (currentBackground != null)
        {
            return currentBackground;
        }

        foreach (Node child in mapInstantiator.GetChildren())
        {
            Sprite2D childBackground = TryGetBackground(child);
            if (childBackground != null)
            {
                return childBackground;
            }
        }

        return null;
    }

    private static Node TryGetCurrentScene(Node mapInstantiator)
    {
        Variant currentSceneValue = mapInstantiator.Get("current_scene");
        if (currentSceneValue.VariantType == Variant.Type.Nil ||
            currentSceneValue.AsGodotObject() is not Node currentScene ||
            !IsInstanceValid(currentScene))
        {
            GD.Print("currentScene is nil or invalid");
            return null;
        }
        GD.Print("currentScene: " + currentScene.Name);
        return currentScene;
    }

    private static Sprite2D TryGetBackground(Node roomScene)
    {
        return roomScene?.GetNodeOrNull<Sprite2D>("Background");
    }
}
