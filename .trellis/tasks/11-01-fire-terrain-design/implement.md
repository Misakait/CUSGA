# 执行与检查

- [x] 读取规范、确认Godot4.7.1与ash_plain、备份用户修改和素材哈希。
- [x] 确认12图、六类完整4×4障碍、16像素网格。
- [x] 实现代理编写paint_fire.py并绘制12图，保存布局、障碍组记录、无桥和全桥预览。
- [x] 主代理检查构图及细节；实现代理清理孤立角点及一角宽细尾并刷新全部预览。
- [x] 检查代理独立审计实际场景、192桥状态、出生和24物资格、完整障碍组、资源配置和修改范围。
- [x] 主代理用Godot编辑器加载全部12图，检查新增错误，保留ash_plain打开，不启动游戏。
- [x] 同步验收记录、git diff --check和真实状态，不提交或推送。

实现代理拥有fire全部tscn、paint_fire.py及预览。检查代理在实现结束后拥有check_fire.py、静态报告和必要局部修复。主代理负责规划、编辑器检查与最终验收；不能回滚他人改动。

备份：research/ash_plain.before.tscn、research/before/；基线：research/protected_baseline.json。

预览使用含Pillow的内置Python：C:/Users/huhu9/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe。系统python没有Pillow。

## 验收结果

12图独立构图，合计360个无碰撞装饰、47组完整4×4障碍，六种障碍均已使用。原16个图层的非布局配置及完整资源链与ash_plain参考一致。新增的Ground细节层无碰撞；容器Z顺序让地形、障碍和装饰位于玩家下方。

独立检查报告见research/independent_review.json；检查基于实际场景的多边形和8像素采样，不替代物理引擎验证。Godot4.7.1编辑器逐图加载报告见research/editor_validation.json；12图均加载成功，旧316条日志前后不变，新增0条。未运行游戏，实际游玩由用户验证。

本轮不改脚本或游戏机制，模块文档与机制汇总无需改动。未提交或自动归档任务，避免触发Trellis自动提交。
