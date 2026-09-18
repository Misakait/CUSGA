# .husky 目录说明

这个目录是本项目的 Git 提交钩子（pre-commit hook）配置。每次执行 `git commit` 时，Git 会自动运行它们。

> **读这一页的时机**：你刚 clone 下这个项目，或者你提交时看到 `[gdlint]` 开头的提示，想知道那是什么。

---

## 提交时会跑两个检查

| 顺序 | 检查 | 需要什么才能跑 |
|---|---|---|
| 1 | 用 `dotnet format` 格式化本次改动的 C# 文件 | .NET SDK（项目本来就需要） |
| 2 | 用 `gdlint` 检查本次改动的 GDScript（`.gd`）文件 | **需要额外安装 gdtoolkit，见下** |

配置在 `task-runner.json`，两个检查分别属于 `pre-commit` 和 `pre-commit-gdscript` 两个分组，由 `pre-commit` 文件依次调用。

---

## GDScript 检查需要手动安装 gdtoolkit

### 为什么不能直接放进仓库

`gdlint` 是由 Python 包 **gdtoolkit** 提供的。Windows 上安装后会生成一个 `gdlint.exe`，它是一个只有几十 KB 的"启动垫片"，里面**写死了本机的绝对路径**（例如 `C:\Users\<你的用户名>\AppData\Roaming\uv\tools\gdtoolkit\Scripts\python.exe`）。

所以那个 `.exe` 复制给别人就用不了。同理，把整个 Python 环境（约 7.3 MB、699 个文件，还包含平台和 Python 版本专属的编译文件）提交进仓库也不可行。**因此走"声明依赖 + 各自安装"的方式**，这和项目里 husky 的做法一致（husky 通过 `.config/dotnet-tools.json` 声明，而不是把二进制放进仓库）。

### 安装命令

推荐用 `uv`（本机已用它安装）：

```powershell
uv tool install gdtoolkit==4.5.0
```

**为什么锁定 `==4.5.0` 版本**：gdtoolkit 升级后可能新增或改变检查规则，那样同一份代码在不同人的机器上会报出不同结果。锁死版本可以保证全项目结论一致。

如果已经装过、但 `gdlint` 报类似 `uv trampoline failed to canonicalize script path` 的错误，说明安装环境损坏了（常见于工具环境被删除后垫片残留），用这条修复：

```powershell
uv tool install gdtoolkit==4.5.0 --force
```

### 没装会怎样

**不会阻止你提交。** 脚本会打印下面两行，然后正常放行：

```text
[gdlint] SKIPPED - gdlint not found on PATH.
[gdlint] Install or repair it with: uv tool install gdtoolkit==4.5.0 --force
```

也就是说，不装 gdtoolkit 只是**少了风格提醒**，不影响你提交、也不影响游戏运行。

---

## 这个检查到底在检查什么（重要，别误解）

`gdlint` 是**风格检查器**，不是**语法检查器**。

| 检查什么 | 由谁负责 | 需要 gdtoolkit 吗 |
|---|---|---|
| GDScript **语法错误** | Godot 编辑器、Godot 运行时 | 不需要 |
| GDScript **类型错误** | Godot 编辑器 | 不需要 |
| GDScript **风格是否符合官方建议** | `gdlint` | 需要 |

`gdlint` 输出的信息里带 `Error` 字样，**但那不代表你的语法错了**，只代表"违反了某条风格规则"。真正的语法检查用 `gdparse`，语法正确时它返回退出码 `0`。

`gdlint` 的规则主要来自 **Godot 官方风格指南**（`gdscript_styleguide.rst` 的 Code order 一节，以及 "Keep individual lines of code under 100 characters"）。但那份指南自己也写明"**风格指南不是硬性规则手册**……在自己的项目和团队内保持一致，比严格遵循这份指南更重要"。

### 当前是"只提示、不拦截"

脚本**无论发现多少问题都返回退出码 0**，因此不会拦截提交。

原因：接入时实测本项目 94 个 `.gd`（不含 `addons/`）里有 **63 个文件共 500 条**风格问题，都是历史遗留。如果做成"报错就拦提交"，那么任何人只要碰这些文件就无法提交。

**是否收紧为硬性拦截，由项目所有者决定。** 收紧前需要先把存量问题清理到可接受程度。

---

## 想调整规则怎么办

规则配置在项目根目录的 **`.gdlintrc`**。要关闭某条规则，在它的 `disable:` 列表里加一行规则名即可。

查看全部规则及默认值的命令：

```powershell
gdlint --dump-default-config
```

如果想确认某条提示对应哪条规则：gdlint 的输出末尾会用括号标注规则名，例如
`Error: Max allowed line length (100) exceeded (max-line-length)` 里的 `max-line-length` 就是规则名。
