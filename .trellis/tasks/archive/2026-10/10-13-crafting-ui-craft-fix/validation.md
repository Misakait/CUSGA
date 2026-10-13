# 修复与验证结果

## 根因

新场景调整了按钮与数量控件的位置，根控制器保留旧路径，get_node_or_null 返回 null 并跳过信号连接。修复前真实游戏进程确认 button.pressed 连接数为 0、控制器两个引用均为空、数量与最小值均为 0。这次缺陷与上一轮类型缓存报错分开，当前 CraftingUI 和 Main 均可正常加载。

## 实现

- 控制器使用场景实际 SpinBox 路径及已有唯一按钮名，缺少必需控件时报告错误。
- 数量默认、最小、步进均为 1，要求整数，点击先 apply 文本再捕获请求次数，避免库存变化同步刷新改写本次次数。
- 未绑定、空配方、无材料/空间时禁用，补料后按库存信号恢复。
- 未修改场景美术、制作服务、配方与材料数值。同步建筑文档、游戏机制汇总与 UI 规范。

## Godot 4.7.1 编辑器证据

- filesystem_manage scan 成功，保持 CUSGA 编辑器打开。
- test_run(suite="crafting_ui_contract")：1 用例通过，7 项结构断言。
- 自定义运行 CraftingUI，editor_manage game_eval 调用 run_runtime_checks：29 项检查，failures=[]，passed=true。检查真实生产场景、库存和制作组件，包含默认单次、两次、未失焦文本输入、耗尽、补料、空配方以及禁用信号无副作用。审查的纯换行修正后重新通过。
- Main 自定义运行无启动错误；GameplayPort 信号打开真实 CraftingUI，组件绑定正确，数量 1，按钮可用。完成开局卡抽取后通过 input_mouse 对按钮中心按下/抬起，真实合成火把一次：产物 0→1，材料树枝 6→4、木炭 3→2，符合配方 2树枝+1木炭→1火把。
- 截图显示数量1、合成按钮与材料显示正常；游戏日志显示“成功合成了 1 个 火把！”，没有本次脚本或资源加载错误。
- 全部游戏运行结束调用 project_manage(stop)，未关闭编辑器。
- git diff --check 通过。

## 既有问题及边界

- test_run 发现其他 test_item_room_content.gd 的 Parse error；该套件不属于制作改动，本轮首次测试时即出现，未修改。目标套件确实执行并通过，真实 CraftingUI/Main 游戏进程无此错误。
- 编辑器 test_run 有 preload 缓存警告；首次新结构测试读取旧常量失败，已改当前源码读取；运行时行为在新游戏进程验证，未为清缓存关闭编辑器。
- gdlint 的既有 Open/Close、GameplayPortPath/TooltipPanelPath 命名不符合其默认命名规则，保留稳定公共协议，不擅自重命名。
- agent.local.md 为用户任务前未追踪文件，未改动。没有 Git commit 或 push。

## 最终审查

Trellis 检查代理确认行为符合 PRD，自修19处超长行并修正两份关联文档既有篝火配方错误：当前资源为1树枝→1篝火牌，资源未覆盖材料 Amount 与 OutputAmount，均取脚本默认1；未改配方资源。换行后重新通过编辑器结构测试及29项运行回归。验收清单全部完成，任务按用户授权归档，使用 --no-commit 保留未提交工作供用户审阅。
