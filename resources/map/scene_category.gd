extends Resource
class_name SceneCategory

## 场景类别枚举
## 决定场景在群系生成时的连接数范围和放置优先级
enum Category {
	MAIN,        ## 主场景 — 2~4 通道，群系核心节点
	TRANSITION,  ## 过渡场景 — 1~2 通道，连接主场景的路径
	TELEPORT,    ## 传送场景 — 3~4 通道，跨群系连接枢纽
	MARKET,      ## 集市场景 — 3~4 通道，群系内部交易中心
}
