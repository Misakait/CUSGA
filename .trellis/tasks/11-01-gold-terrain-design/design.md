# 设计与边界

生产只修改scenes/map_scenes/map_env/gold/**/*.tscn。离线绘图工具和预览置于本任务，运行时无生成脚本依赖。所有输入固定research/before备份，不读已生成场景作为再次生成输入。

按真实金生态图集确认每行材质和四角掩码列；沿用经验证的四角拼接/碰撞边界数学，12张构图重新独立编排。主题分别为铜锈、齿轮、金沙、铁脊、磁铁矿、合金裂谷、磁铁丘陵、矿脉、锈原、冶炼遗迹、钢穹交换所与钢穹之门。中央资源区域保持完整地表，可在侧边绘制中空、凹湾、阶梯和锯齿轮廓。

参考图全部子资源链保留，含CompressedTexture2D导入load_path；逐层迁移非布局参数，其余节点身份/UID/根配置/资源引用保留。Ground普通层与细节无碰撞，Boundary常设，BridgeWithBoundary关向封口，BridgeBoundary开向桥侧阻挡。桥约3格长，桥色随引道。Obstack层清空，仅保留原结构和资源。

容器Z顺序Ground=-5、Boundary=-4、BridgeContainer和BridgeWithBoundary=-3、BridgeBoundary和Obstack=-2，Decorations=-1；玩家默认0。装饰无碰撞、避开出生/物资格/桥口。

备份所有12图及保护哈希；检查实际tscn而非生成清单。Godot编辑器唯一由主代理访问，先记录日志基线，完工逐图强制重载、节点检查、日志差分后回到copper_rust_forest。不运行游戏。
