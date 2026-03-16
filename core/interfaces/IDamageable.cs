using CUSGA.core.constants;
namespace CUSGA.core.interfaces;

public interface IDamageable
{
	void TakeDamage(int amount, ElementType element_type);
}
