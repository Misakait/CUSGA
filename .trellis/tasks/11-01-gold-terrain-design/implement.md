# 执行与检查

- [x] 读取规则，确认Godot4.7.1/current copper_rust_forest和12图。
- [x] 备份原场景/资源哈希，确认图集与参考配置。
- [x] 实现代理绘制全部gold场景、清空obstacle、添加装饰、保存无桥/全桥预览。
- [x] 主代理目视审查无桥/全桥总览及齿轮荒原大图，确认12图独立构图。
- [x] 独立检查代理读取最终12图，检查原配置/资源链、空obstacle、四角接缝、192桥状态、出生/24物资格和保护哈希。
- [x] 主代理Godot逐图加载，比较新增日志，保留copper_rust_forest打开。
- [x] 复读报告与git diff --check，写验收记录。不提交推送。

实现代理拥有gold全部tscn和paint_gold.py及预览。审查代理拥有check_gold.py及静态报告；需要场景修正先协调并由生成器修复。主代理负责规划、Godot加载及验收。双方不是独自工作，不回滚他人修改。

Pillow Python：C:/Users/huhu9/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe。

## 最终验收

12图完成，Obstack使用瓦片总计0，原16层非布局配置与完整资源链保留。每图30个装饰，总计360个；Decorations无碰撞、Z=-1，玩家下方显示。全部192桥组合、出生与24物资格静态检查通过，桥长48像素且与引道同材质，Ground全部层特殊角片及接缝检查通过。保护哈希仅gold12图发生变化。

Godot4.7.1编辑器12图加载成功，无新增日志（旧34条前后不变）。当前铜锈之森初次切回显示旧缓存，成为当前场景后再次force_reload已确认59节点/19瓦片层/30装饰；未保存旧副本。没有启动游戏，物理引擎与游玩验证留给用户。

证据：research/editor_validation.json、independent_review.json、review.md；复现静态检查：python .trellis/tasks/11-01-gold-terrain-design/check_gold.py。仅场景绘制，无公共功能或玩法数值变化，现有规范和模块文档无需扩展。不运行带自动提交的归档或日志命令。
