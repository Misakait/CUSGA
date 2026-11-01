# 执行步骤

- [x] 确认 Godot 4.7.1 连接 CUSGA、当前 coral_shoal，读取用户修改及参考图集。
- [x] 备份 coral_shoal，记录场景、脚本、地图资源与素材基线哈希。
- [x] 明确四角掩码、三类边界与 1280×720 房间步长。
- [x] 写入 12 图独立轮廓、材质与装饰布局，迁移参考资源。
- [x] 检查所有角点拼接、16 种桥组合和物资格可达性，修正问题。
- [x] 生成无桥及有桥预览，查看代表图细节。
- [x] 通过 Godot 编辑器加载全部 12 图并读取日志，保留 coral_shoal 打开；不运行游戏。
- [x] 复核只修改 water 与本任务产物，记录结果。不提交或推送 Git。

## 回退点

coral_shoal 用户原始版本为 research/coral_shoal.before.tscn。其他场景首次写入前备份到 research/before/；生成器重复运行必须读取备份，不能把上轮输出当源文件。素材哈希以 research/protected_baseline.json 为准。
