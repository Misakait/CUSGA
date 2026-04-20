namespace CUSGA.core.combat.status;

public enum DurationExpirePolicy
{
    // 任意一个已配置的 duration 到 0 就过期
    FirstExpired,

    // 所有已配置的 duration 都到 0 才过期
    AllExpired
}
