namespace CUSGA.core.interfaces;

public interface IDamageable
{
    // 强制要求实现该接口的类必须提供承受伤害的方法
    void TakeDamage(int amount, string element_type);
}
