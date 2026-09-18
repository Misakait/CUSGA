# CUSGA Project - AI Agent Core Directives

> **CRITICAL: READ BEFORE EXECUTING ANY COMMANDS OR WRITING CODE.**
> The following project-specific rules take absolute precedence over your default behaviors.
> Check if agent.local.md exists in the root directory. If yes, read it and let its rules override the ones below.

## 1. Compilation & Validation Rules (CRITICAL SANDBOX CONSTRAINT)

- **The Trap**: Running standard `dotnet test` or `dotnet build` triggers local Husky hooks that attempt to write to `.git/config`. Your sandbox lacks these permissions and will fatally crash.
- **NEVER DO**: You must NEVER trigger or attempt to modify `.git/config` hooks under any circumstances.
- **ALWAYS DO (Dynamic Evaluation)**: When you need to verify compilation, you **MUST** prepend `env CI=true` to bypass hooks. However, you must dynamically determine the correct target based on the project structure:
  - First, survey the workspace. Are there `.sln` files or multiple `.csproj` files?
  - If it's a simple project, build the specific project (e.g., `env CI=true dotnet build [TargetProject].csproj --no-restore`).
  - If it's a complex solution and the change spans multiple areas, build the solution (e.g., `env CI=true dotnet build [SolutionName].sln --no-restore`).
  - _Do NOT blindly copy these examples; adapt the target file to the actual context._
- **Godot Runtime Validation**: When a change touches GDScript, `.tscn` scenes, Godot resources, C# `[GlobalClass]` types, autoload access, or scene/runtime integration, validate through the **Godot editor MCP** (`addons/godot_ai`) in addition to `dotnet build`.
  - **Do NOT use the `godot-mono` command line.** This machine's CLI is Godot 4.6.3 while the project and `addons/godot_ai` require 4.7.1, so `--build-solutions` aborts outright. See "Superseded practices" below for the full list of what no longer works.
  - **Precondition**: the Godot editor must be **open** with the CUSGA project loaded. Verify with `editor_state` / `session_manage(op="list")` before validating. If no session is connected, ask the user to open Godot rather than falling back to the command line.
  - The MCP tool set that replaces the old CLI flags:

    | Old CLI flag | Replacement (editor MCP) | What it covers |
    |---|---|---|
    | `--build-solutions --quit` | `env CI=true dotnet build CUSGA.sln --no-restore` | C# compile; the editor reloads `CUSGA.dll` itself |
    | `--scene res://X.tscn --quit-after N` | `project_run(mode="custom", scene="res://X.tscn")` + `logs_read(source="game")`, then `project_manage(op="stop")` | scene loads, scripts compile, node paths, autoload wiring |
    | `--script res://tests/godot/x.gd` | `test_run(suite=..., test_name=...)` | focused runtime test runners under `tests/godot/` |
    | `--check-only --script` | *(no replacement — do not use)* | see below; it never worked for autoload-referencing scripts |
    | manual screenshot | `editor_screenshot` (`source` = `game` or `viewport`) | visual confirmation for UI changes |
    | debug prints | `game_eval(code=...)` / `game_command` | interactive assertions inside the running game |

  - Smoke-test the changed scene path, and usually the main scene too, via `project_run(mode="custom", scene=...)` followed by `logs_read(source="game")`. Stop the game with `project_manage(op="stop")`.
  - Treat `SCRIPT ERROR`, `Parse Error`, `Failed to load script`, and C# build failures as blockers. Resource UID warnings may be pre-existing; only treat them as blockers when they involve files touched by the current change.
  - Do not rely on plain `dotnet run` for Godot-dependent test runners; it can fail to locate `GodotSharp` outside the Godot runtime. Use `test_run` (editor MCP) for runtime/script/scene validation and `env CI=true dotnet build ... --no-restore` for compile validation.
  - Running the Godot editor rewrites version-controlled files: it reformats `.cs` indentation from spaces to Tab (violating `.editorconfig`) and rewrites `CUSGA.csproj`'s `Godot.NET.Sdk` version. Always `git status` afterwards and revert unintended changes.

### Superseded practices (do not follow older docs that still list them)

Older project docs — including parts of `.trellis/spec/frontend/quality-guidelines.md`, `.trellis/spec/backend/testing-guidelines.md`, and `.trellis/spec/guides/minimal-feature-start.md` — still describe `godot-mono --headless` validation. Those instructions are **obsolete** and this section overrides them:

- `--build-solutions` **fails on this machine** — the 4.6.3 CLI conflicts with `addons/godot_ai`, which requires Godot ≥ 4.7.
- `--check-only --script` is **not usable as a gate** — it only parses and does not compile, so any script referencing an autoload fails with `Identifier not found: <AutoloadName>`. Pre-existing scripts behave the same way; do not treat that failure as a regression, and do not use the flag as a pass/fail criterion.
- `--script` mode **does not load autoloads**, so C# autoloads (`PlayerWallet`, `PlayerProgression`, …) resolve to `null` there. Scenes depending on them must be validated in a real running game.
- The correct compile command is always `env CI=true dotnet build CUSGA.sln --no-restore`; the correct runtime validation path is the editor MCP.

## 2. Documentation & Commenting Standards

- **XML/Standard Docs**: Always include standard XML docs (or equivalent docstrings) for all public classes, methods, and functions. You must explicitly explain parameters and return values.
- **Inline Complexity**: Add inline comments for any complex, non-obvious, or algorithmic logic (e.g., Crafting settlement, combat state transitions).
- **Explain the "Why"**: Comments must focus on explaining WHY a specific approach was taken, not merely narrating WHAT the code is doing.
- **Zero-Sacrifice Clarity**: Keep the code clean, but NEVER sacrifice necessary explanatory comments for the sake of brevity.
- **Native Comment Language**: Write all code comments in Chinese language.

---

<!-- CODEGRAPH_START -->

## CodeGraph

> **STATUS: CONFIGURED BUT NOT OPERATIONAL — DO NOT RELY ON IT.**
> `.codegraph/` contains only `config.json` and `.gitignore`. No index has ever been built, the CLI is not reachable (the npm package name `codegraph` has no runnable executable; `npx codegraph` fails with "could not determine executable to run"), and **no `codegraph_*` MCP tools are registered in this session**. Every call would fail with "not initialized".
> **Use GitNexus instead** (it is the tool actually installed here — see the section below) plus native `rg` / read tools.
> The guidance below is kept so the section is ready if the owner decides to build the index. Until then, treat it as inactive.

### GDScript is not covered, and cannot be (verified 2026-09-19)

This is **not** a missing-index problem — it is a language-support limit, so building the index would not fix it:

- `.codegraph/config.json` has an explicit `include` list of file extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`, `.java`, `.c`, `.h`, `.cpp`, `.hpp`, `.cc`, `.cxx`, `.cs`, `.php`, `.rb`, `.swift`, `.kt`, `.kts`, `.dart`, `.svelte`, `.liquid`, `.pas`, `.dpr`, `.dpk`, `.lpr`, `.dfm`, `.fmx`). **`.gd` is absent.** The tool walks the files it is configured for, so adding GDScript is not a config toggle.
- GitNexus does not cover GDScript either, and it is the same class of tool (parser-based symbol graph).

**Consequence — this is the agreed workflow, not a gap to fill:**

- C# symbols, callers, callees, and impact analysis → **GitNexus**.
- GDScript symbols, scene scripts, and Godot runtime behaviour → **native `rg` / read tools, then runtime validation through the editor MCP** (`test_run` / `project_run` + `logs_read(source="game")`), as described in section 1.
- Never hand-edit or hand-extend `.codegraph/config.json` to try to add `.gd`; that would produce a silently incomplete graph, which is worse than having no graph.

This item was previously listed as an open improvement ("make CodeGraph / GitNexus cover `.gd`"). It is now **closed as not achievable**; do not re-raise it.

This project has a CodeGraph MCP server (`codegraph_*` tools) configured. CodeGraph is a tree-sitter-parsed knowledge graph of every symbol, edge, and file. Reads are sub-millisecond and return structural information grep cannot.

### When to prefer codegraph over native search

Use codegraph for **structural** questions — what calls what, what would break, where is X defined, what is X's signature. Use native grep/read only for **literal text** queries (string contents, comments, log messages) or after you already have a specific file open.

| Question                                      | Tool                |
| --------------------------------------------- | ------------------- |
| "Where is X defined?" / "Find symbol named X" | `codegraph_search`  |
| "What calls function Y?"                      | `codegraph_callers` |
| "What does Y call?"                           | `codegraph_callees` |
| "What would break if I changed Z?"            | `codegraph_impact`  |
| "Show me Y's signature / source / docstring"  | `codegraph_node`    |
| "Give me focused context for a task/area"     | `codegraph_context` |
| "Survey an unfamiliar module/topic"           | `codegraph_explore` |
| "What files exist under path/"                | `codegraph_files`   |
| "Is the index healthy?"                       | `codegraph_status`  |

### Rules of thumb (hypothetical — CodeGraph cannot actually be enabled here; see the STATUS note)

- **Trust codegraph results.** They come from a full AST parse. Do NOT re-verify them with grep — that's slower, less accurate, and wastes context.
- **GDScript caveat:** CodeGraph and GitNexus do not index `.gd` files in this project. For GDScript symbols, scene scripts, and Godot runtime behavior, use native search/read tools such as `rg` and validate through the editor MCP (`test_run` / `project_run` + `logs_read(source="game")`) as described in section 1.
- **Don't grep first** when looking up a symbol by name. `codegraph_search` is faster and returns kind + location + signature in one call.
- **Don't chain `codegraph_search` + `codegraph_node`** when you just want context — `codegraph_context` is one call.
- **`codegraph_explore` is the heavy hitter** for unfamiliar areas — it returns full source from all relevant files in one call, but is token-heavy. If your harness supports parallel subagents (e.g., Claude Code's Task tool), spawn one for explore-class questions to keep main session context clean.
- **Index lag**: the file watcher debounces ~500ms behind writes; don't re-query immediately after editing a file in the same turn.

### If `.codegraph/` doesn't exist

`.codegraph/` **does** exist here, but it holds only `config.json` and `.gitignore` — there is no index, so the MCP server answers "not initialized." That is the current expected state; see the STATUS note at the top of this section.

Do **not** silently run `codegraph init -i`. The CLI is not obtainable on this machine (the npm package `codegraph` has no runnable executable), and building an index would still not give GDScript coverage — see the note above. Treat CodeGraph as unavailable and use GitNexus plus native search.

<!-- CODEGRAPH_END -->

<!-- gitnexus:start -->

# GitNexus — Code Intelligence

This project is indexed by GitNexus as **CUSGA** . Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource                               | Use for                                  |
| -------------------------------------- | ---------------------------------------- |
| `gitnexus://repo/CUSGA/context`        | Codebase overview, check index freshness |
| `gitnexus://repo/CUSGA/clusters`       | All functional areas                     |
| `gitnexus://repo/CUSGA/processes`      | All execution flows                      |
| `gitnexus://repo/CUSGA/process/{name}` | Step-by-step execution trace             |

## CLI

| Task                                         | Read this skill file                                        |
| -------------------------------------------- | ----------------------------------------------------------- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md`       |
| Blast radius / "What breaks if I change X?"  | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?"             | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md`       |
| Rename / extract / split / refactor          | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md`     |
| Tools, resources, schema reference           | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md`           |
| Index, status, clean, wiki CLI commands      | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md`             |

<!-- gitnexus:end -->
