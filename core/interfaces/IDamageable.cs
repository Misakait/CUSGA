using CUSGA.core.constants;
namespace CUSGA.core.interfaces;

public interface IDamageable
{
    /// <summary>
    /// 对目标造成伤害并返回实际扣除的生命值。
    /// </summary>
    /// <param name="amount">尝试造成的伤害量。</param>
    /// <param name="elementType">伤害五行属性。</param>
    /// <returns>返回受当前生命值限制后的实际扣血量。</returns>
    int TakeDamage(int amount, ElementType elementType);
}
