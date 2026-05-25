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
- **Godot Runtime Validation**: When a change touches GDScript, `.tscn` scenes, Godot resources, C# `[GlobalClass]` types, autoload access, or scene/runtime integration, validate with `godot-mono --headless` in addition to `dotnet build`.
  - Build Godot's C# solution and refresh global classes with:
    - `godot-mono --headless --path . --build-solutions --quit`
  - Parse-check every changed GDScript file when practical:
    - `godot-mono --headless --path . --check-only --script res://path/to/script.gd`
  - Run focused Godot runtime test runners when they exist for the changed area:
    - `godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd`
  - Smoke-test the changed scene path, and usually the main scene too:
    - `godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5`
    - `godot-mono --headless --path . --scene res://path/to/changed_scene.tscn --quit-after 5`
  - In sandboxed environments, `godot-mono --headless --build-solutions` may need approval/escalation because Godot writes editor settings/build logs under the user config directory and opens a local editor messaging socket. If it fails with permission errors, rerun the same command with the proper escalation flow instead of treating it as a project failure.
  - Treat `SCRIPT ERROR`, `Parse Error`, `Failed to load script`, and C# build failures as blockers. Resource UID warnings may be pre-existing; only treat them as blockers when they involve files touched by the current change.
  - Do not rely on plain `dotnet run` for Godot-dependent test runners; it can fail to locate `GodotSharp` outside the Godot runtime. Prefer `godot-mono --headless` for runtime/script/scene validation and `env CI=true dotnet build ... --no-restore` for compile validation.

## 2. Documentation & Commenting Standards

- **XML/Standard Docs**: Always include standard XML docs (or equivalent docstrings) for all public classes, methods, and functions. You must explicitly explain parameters and return values.
- **Inline Complexity**: Add inline comments for any complex, non-obvious, or algorithmic logic (e.g., Crafting settlement, combat state transitions).
- **Explain the "Why"**: Comments must focus on explaining WHY a specific approach was taken, not merely narrating WHAT the code is doing.
- **Zero-Sacrifice Clarity**: Keep the code clean, but NEVER sacrifice necessary explanatory comments for the sake of brevity.
- **Native Comment Language**: Write all code comments in Chinese language.

---

<!-- CODEGRAPH_START -->

## CodeGraph

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

### Rules of thumb

- **Trust codegraph results.** They come from a full AST parse. Do NOT re-verify them with grep — that's slower, less accurate, and wastes context.
- **GDScript caveat:** CodeGraph and GitNexus do not index `.gd` files in this project. For GDScript symbols, scene scripts, and Godot runtime behavior, use native search/read tools such as `rg` and validate with focused `godot-mono --headless` runners.
- **Don't grep first** when looking up a symbol by name. `codegraph_search` is faster and returns kind + location + signature in one call.
- **Don't chain `codegraph_search` + `codegraph_node`** when you just want context — `codegraph_context` is one call.
- **`codegraph_explore` is the heavy hitter** for unfamiliar areas — it returns full source from all relevant files in one call, but is token-heavy. If your harness supports parallel subagents (e.g., Claude Code's Task tool), spawn one for explore-class questions to keep main session context clean.
- **Index lag**: the file watcher debounces ~500ms behind writes; don't re-query immediately after editing a file in the same turn.

### If `.codegraph/` doesn't exist

The MCP server returns "not initialized." Ask the user: _"I notice this project doesn't have CodeGraph initialized. Want me to run `codegraph init -i` to build the index?"_

<!-- CODEGRAPH_END -->

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **CUSGA** (3192 symbols, 7136 relationships, 199 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

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

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/CUSGA/context` | Codebase overview, check index freshness |
| `gitnexus://repo/CUSGA/clusters` | All functional areas |
| `gitnexus://repo/CUSGA/processes` | All execution flows |
| `gitnexus://repo/CUSGA/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
