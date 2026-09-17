using CUSGA.core.shop;
using Godot;

namespace CUSGA.core.autoloads;

/// <summary>
/// 持有玩家金币的全局自动加载节点，并在每次变动后把余额持久化到本地设置文件。
/// </summary>
/// <remarks>
/// 之所以需要这个全局节点：<c>GlobalEventBus</c> 只广播信号、<c>ItemsControl</c> 管物品表、
/// <c>GlobalWarehouse</c> 管仓库库存、<c>SettingsManager</c> 管配置读写，没有任何一个 autoload 持有玩家货币。
/// 货币天然要被仓库、商店以及后续的合成与局内流程共享，不存在单一的局部拥有者，因此新增是合理的。
/// <para>
/// 实现 <see cref="IPlayerWallet"/> 而不是让商店直接依赖本节点：规则层因此可以在控制台测试里注入假钱包。
/// 这也是钱包必须用 C# 实现的原因——GDScript 类无法实现 C# 接口。
/// </para>
/// </remarks>
public partial class PlayerWallet : Node, IPlayerWallet
{
    /// <summary>本地设置文件中金币所属的分组名。</summary>
    /// <remarks>存储键一旦发布就应当保持稳定，显示文案可以改，键名不可以。</remarks>
    public const string SettingsSection = "player";

    /// <summary>本地设置文件中金币的键名。</summary>
    public const string SettingsKey = "gold";

    /// <summary>没有任何已保存余额时使用的初始金币。</summary>
    /// <remarks>该数值需高于最贵单件商品（金胸甲 1050），让新玩家开局就能买到任意一件商品。</remarks>
    public const int DefaultGold = 1200;

    /// <summary>
    /// 金币余额发生变化时发射，参数为变化后的余额。
    /// </summary>
    /// <param name="gold">变化后的金币余额。</param>
    [Signal]
    public delegate void GoldChangedEventHandler(int gold);

    // 缓存 SettingsManager 节点：余额读写都在每次交易中发生，不应每次沿场景树重新查找。
    private Node _settingsManager;

    public int Gold { get; private set; } = DefaultGold;

    public override void _Ready()
    {
        _settingsManager = GetNodeOrNull<Node>("/root/SettingsManager");
        if (_settingsManager == null)
        {
            // 缺设置服务只应降级为「本次运行内有效」，而不是让游戏起不来。
            GD.PushError("PlayerWallet: 未找到 SettingsManager，金币将只在本次运行内有效。");
        }

        Gold = ReadStoredGold();
    }

    /// <summary>
    /// 尝试扣除指定数量的金币。
    /// </summary>
    /// <param name="amount">需要扣除的金币数量，只有正数才有意义。</param>
    /// <returns>余额足够并完成扣除时为 <see langword="true"/>；否则为 <see langword="false"/> 且余额保持不变。</returns>
    public bool TrySpend(int amount)
    {
        // 非正数扣款没有意义。返回 false 而不是静默成功，避免调用方误以为交易已计价。
        if (amount <= 0 || amount > Gold)
        {
            return false;
        }

        Gold -= amount;
        PersistGold();
        EmitSignal(SignalName.GoldChanged, Gold);
        return true;
    }

    /// <summary>
    /// 增加金币。
    /// </summary>
    /// <param name="amount">需要增加的金币数量；非正数会被忽略。</param>
    /// <remarks>
    /// 忽略非正数是刻意的：<c>Add</c> 只用于进账，若允许负数，购买失败时的退款逻辑就可能被误用成扣款入口。
    /// </remarks>
    public void Add(int amount)
    {
        if (amount <= 0)
        {
            return;
        }

        // 用 64 位累加再钳制，避免大额收益把余额回绕成负数。
        long total = (long)Gold + amount;
        Gold = total > int.MaxValue ? int.MaxValue : (int)total;
        PersistGold();
        EmitSignal(SignalName.GoldChanged, Gold);
    }

    /// <summary>
    /// 从本地设置文件读取余额，并对存档内容做领域校验。
    /// </summary>
    /// <returns>通过校验的余额；缺失或非法时返回 <see cref="DefaultGold"/>。</returns>
    /// <remarks>
    /// 存档是玩家本机文件，可能被手工改成字符串或负数。调用方负责校验领域值并回退默认值，
    /// 这是 <c>SettingsManager</c> 的既定契约——它只负责读写，不理解金币的合法范围。
    /// </remarks>
    private int ReadStoredGold()
    {
        if (_settingsManager == null)
        {
            return DefaultGold;
        }

        Variant stored = _settingsManager.Call("get_setting", SettingsSection, SettingsKey, DefaultGold);

        // 首次运行时 SettingsManager 会原样返回传入的默认值，因此这两种数值类型是唯一合法形态。
        if (stored.VariantType != Variant.Type.Int && stored.VariantType != Variant.Type.Float)
        {
            GD.PushWarning("PlayerWallet: 存档中的金币不是数值，已回退到默认值。");
            return DefaultGold;
        }

        int value = stored.AsInt32();
        if (value < 0)
        {
            GD.PushWarning("PlayerWallet: 存档中的金币为负数，已回退到默认值。");
            return DefaultGold;
        }

        return value;
    }

    /// <summary>
    /// 把当前余额写入本地设置文件。
    /// </summary>
    /// <remarks>
    /// 写盘失败只记录警告：内存中的余额仍然有效，当前会话继续使用新值，
    /// 但不能对外声称金币已经跨重启保存成功。
    /// </remarks>
    private void PersistGold()
    {
        if (_settingsManager == null)
        {
            return;
        }

        Variant saved = _settingsManager.Call("set_setting", SettingsSection, SettingsKey, Gold);

        // SettingsManager 约定返回 bool 表示落盘是否成功；其他形态说明契约变了，同样按失败处理。
        if (saved.VariantType != Variant.Type.Bool || !saved.AsBool())
        {
            GD.PushWarning("PlayerWallet: 金币未能写入本地设置文件，本次运行内仍然有效。");
        }
    }
}
