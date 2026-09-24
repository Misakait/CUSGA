# Repository Analysis

The goal is to discover the project's real architecture before writing rules. Do not start from generic spec templates and fill blanks. Start from the code, then let the spec structure follow.

## Analysis Order

1. Read the existing `.trellis/spec/` tree and note which files are templates, outdated, or already project-specific.
2. Inspect package manifests, build scripts, workspace config, and top-level documentation to identify packages and runtime layers.
3. Use `rg` to trace script, scene, resource, signal, node-path, and autoload references.
4. Use the Godot editor MCP to inspect the running scene and validate dynamic node wiring.
5. Read representative GDScript, scene, resource, and test files directly before turning any finding into a spec rule.

## What To Capture

| Area | Questions |
|------|-----------|
| Package boundaries | What does each package own? What imports cross boundaries? |
| Runtime layers | Which code is CLI, backend, frontend, worker, shared library, test-only, or tooling? |
| Core abstractions | Which types, services, stores, commands, routes, or adapters define the system shape? |
| Data flow | Where does user input enter, how is it validated, and where does state persist? |
| Error handling | How are failures represented, logged, surfaced, and tested? |
| Configuration | Where do defaults, environment config, generated files, and templates live? |
| Tests | Which test styles are trusted examples for new work? |

## Godot GDScript Analysis

Use native repository search for static relationships:

```text
rg -n "class_name|signal|\.instantiate\(|get_node\(|preload\(|load\(" --glob "*.gd" --glob "*.tscn" --glob "*.tres"
```

Use the Godot editor MCP for runtime relationships: start the affected scene, read game logs, evaluate focused assertions, and stop only the game process. Keep the editor open.

## Analysis Notes

Keep short notes while analyzing. The notes should include:

- Package or layer name.
- Files that define the local pattern.
- Rules the spec should teach.
- Anti-patterns found in old code, comments, tests, or migration paths.
- Spec files that should be created, deleted, renamed, or merged.
