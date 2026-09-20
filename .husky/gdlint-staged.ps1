# 提交前 GDScript 静态检查（gdlint）
#
# 用途：在提交前检查「本次暂存的 .gd 文件」，把新引入的风格/命名问题当场报出来。
#
# 为什么只查暂存文件，而不是全量：
#   项目存量代码有约 500 条 gdlint 报错（63 个文件），全量检查等于每次提交刷 500 条噪音，
#   结果就是没人再看得懂输出。
#
# 为什么不拦截提交：
#   存量问题未清理完，一旦做成硬门禁，任何改动这些文件的提交都会失败，仓库会卡死。
#   因此本脚本**始终返回 0**，只提示、不拦截。是否收紧由项目所有者决定。
#
# 为什么放在独立脚本而不是直接写进 task-runner.json：
#   过滤 + 循环 + 统计的逻辑写成 JSON 单行会又长又难改，也会让中文注释没地方写。
#
# 本文件必须保存为「UTF-8 带 BOM」：
#   PowerShell 5.1 读取不带 BOM 的 .ps1 时会按系统 ANSI 代码页解析，中文注释会变乱码并
#   导致语法错误（实测报 "The string is missing the terminator"）。改用带 BOM 的 UTF-8 即可解决。

# 注意：这里**不能**设成 'Stop'。
# 原因：gdlint 把问题写到标准错误（stderr）。在 PowerShell 5.1 下，「原生命令写 stderr」会被
# 当成终止性错误，导致脚本中途中断、钩子返回非 0（实测退出码 1），于是本该「只提示」的检查
# 就变成了「拦提交」。本脚本的设计目标是始终返回 0，所以这里必须保持 'Continue'。
$ErrorActionPreference = 'Continue'

# 下面所有 Write-Host 的运行期文案刻意使用纯 ASCII。
# 原因：PowerShell 5.1 输出中文时使用系统 ANSI 代码页，在非 GBK 终端里会显示成乱码
# （实测在 UTF-8 与 en-US 环境下均乱码），且该行为无法可靠修正。
# 输出可读性优先，因此运行期文案用英文；详细中文说明保留在本文件的注释里。
# gdlint 自身产生的报告本来就是英文。

# 先确认 gdlint 真的能跑。若 gdtoolkit 缺失或安装损坏，给出可操作的提示，而不是让提交失败。
if (-not (Get-Command gdlint -ErrorAction SilentlyContinue)) {
    Write-Host '[gdlint] SKIPPED - gdlint not found on PATH.'
    Write-Host '[gdlint] Install or repair it with: uv tool install gdtoolkit==4.5.0 --force'
    exit 0
}

# 取本次暂存的 .gd 文件。--diff-filter=d 排除「已删除」的文件，删除的文件不需要检查。
$staged = @(git diff --cached --name-only --diff-filter=d -- '*.gd')

if ($staged.Count -eq 0) {
    Write-Host '[gdlint] No staged .gd files - skipped.'
    exit 0
}

# 逐个检查并把输出收集起来。gdlint 会把问题写到标准错误，所以这里合并 2>&1。
$problems = @($staged | ForEach-Object { gdlint $_ 2>&1 } |
    Where-Object { $_ -match 'Error:|Warning:' })

if ($problems.Count -eq 0) {
    Write-Host "[gdlint] OK - $($staged.Count) staged .gd file(s) passed."
    exit 0
}

Write-Host ''
Write-Host "[gdlint] $($problems.Count) problem(s) in staged .gd file(s):"
Write-Host '------------------------------------------------------------'
$problems | ForEach-Object { Write-Host $_ }
Write-Host '------------------------------------------------------------'
Write-Host '[gdlint] This check does NOT block the commit (existing code still has'
Write-Host '[gdlint] ~500 issues, so a hard gate would make the repo uncommittable).'
Write-Host '[gdlint] Please fix the newly introduced ones. Rules: .gdlintrc'

exit 0
