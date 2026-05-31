---
name: architectural-engineering-guidelines
description: "architectural software engineering guidance for code design, refactoring, and system modeling. use when reviewing or writing non-trivial code, designing gameplay systems, backend services, ecs/component systems, ui state systems, data pipelines, os/runtime components, or when the user asks for solid, design patterns, high cohesion, low coupling, maintainability, extensibility, testability, or architecture-first implementation."
---

# Architectural Engineering Guidelines

Core principle: establish architectural boundaries before writing implementation code. Do not patch over unclear design with spaghetti code. Every change should move the system toward higher cohesion, lower coupling, stronger contracts, and better long-term maintainability.

## 0. Response Protocol

When this skill is active, structure architecture-heavy answers in this order:

1. **Domain Model**
   - Identify the core entities, value objects, services, components, data resources, adapters, and external dependencies.
2. **Boundary Decision**
   - State what belongs to data, domain logic, application orchestration, infrastructure/adapters, UI, persistence, and framework integration.
3. **Pattern Choice**
   - Name the architectural style or design pattern being used and explain why it fits the current problem.
4. **Current Design Risks**
   - Identify SRP/OCP/DIP violations, hidden coupling, transaction risks, ownership ambiguity, framework leakage, and state mutation hazards.
5. **Refactor Path**
   - Provide the smallest safe migration path before adding new features.
6. **Success Criteria**
   - Define how the change should be verified: tests, compile checks, invariants, behavior preservation, or manual validation steps.
7. **Code**
   - Write implementation code only after the architectural boundary and success criteria have been declared.
8. **Trade-offs**
   - Explain what complexity was added, what coupling was removed, what was intentionally not abstracted, and what should be deferred.

For small clarification questions, use a compact version of this protocol, but still preserve architecture-first reasoning.

## 1. Architecture Before Implementation

Do not blindly fill in logic. Establish the abstract model first.

Before writing implementation code:

- Identify the core domain entities and their boundaries.
- Identify who owns each piece of state.
- Identify who is allowed to mutate that state.
- Identify which rules are stable and which rules are likely to vary.
- Identify framework-specific code and keep it out of pure domain logic when possible.
- Declare the intended design pattern or architectural style before coding.
- If the current code violates Single Responsibility Principle, Open-Closed Principle, or Dependency Inversion Principle, call that out directly and propose a boundary-level refactor first.

Prefer incremental refactoring over full rewrites unless the existing boundary is fundamentally broken.

## 2. Boundary Model

Separate responsibilities into clear layers.

Recommended boundary categories:

- **Data / Configuration**
  - Static definitions, schemas, constants, resource files, configuration data, metadata.
  - Should not own runtime behavior or mutable application state.

- **Runtime State**
  - Mutable state that changes during execution.
  - Must have a clear owner and a controlled mutation path.

- **Domain Logic**
  - Pure business, game, system, or application rules.
  - Should be testable without framework lifecycle, UI, database, network, or scene/runtime context when possible.

- **Application Orchestration**
  - Coordinates use cases.
  - Calls services, repositories, components, and adapters.
  - Should not contain low-level implementation details.

- **Infrastructure / Adapters**
  - Framework integration, persistence, networking, file I/O, engine-specific APIs, external services.
  - Should adapt external systems to internal contracts.

- **UI / Presentation**
  - Displays state and captures user input.
  - Should call stable application/component APIs instead of directly mutating domain state.

## 3. Domain-Aware Abstraction

Choose abstraction depth based on the execution domain. Do not apply one architectural style everywhere.

### Business, Backend, Tools, and Application Logic

Use stronger interface boundaries, dependency injection, polymorphism, and testable services when:

- Business rules are volatile.
- Multiple implementations are expected.
- The code needs unit testing without external systems.
- The logic coordinates persistence, network, UI, or asynchronous workflows.
- The system is expected to grow in features or integrations.

Separate data state from behavior logic. Keep modules independently testable and avoid framework leakage into domain rules.

### Game Logic, ECS, and Component Systems

Prefer composition over inheritance.

Use:

- Components for ownership and framework integration.
- Plain services for rules and calculations.
- Signals, events, or observers for notifications, not hidden business logic.
- Transaction-style operations for inventory, crafting, rewards, equipment, economy, persistence, and other mutation-heavy systems.

Recommended mutation flow:

1. Validate.
2. Build a plan.
3. Simulate.
4. Commit atomically.
5. Notify observers.

Avoid turning central entities such as player, world, scene, manager, controller, or app classes into god objects.

### Low-Level, Systems, OS, Runtime, Embedded, and Performance-Critical Code

Constrain object-oriented abstraction immediately.

Prefer:

- Data locality.
- Zero-cost abstractions.
- Explicit ownership.
- Strict lifetimes.
- Enum state machines.
- Contiguous memory layouts.
- Clear synchronization boundaries.
- Minimal allocation.
- Predictable control flow.

Avoid:

- Deep inheritance.
- Runtime polymorphism unless justified.
- Allocation-heavy abstractions.
- Hidden ownership transfer.
- Generic managers with unclear memory behavior.
- Framework-like indirection in hot paths.

In these domains, correctness, layout, lifecycle, memory safety, and cache behavior are architectural concerns.

## 4. Interface Boundary Rule

Introduce interfaces at architectural boundaries, not everywhere.

Good interface boundaries:

- A service depends on an inventory, repository, cache, clock, logger, event sink, or external capability.
- A calculator depends on an attribute/stat/provider contract.
- UI depends on a read-only view model or presenter contract.
- A persistence layer depends on a serialization or storage contract.
- A system boundary needs test doubles.
- Multiple implementations already exist or are clearly expected.

Avoid interfaces for:

- Simple data resources.
- Private helper logic.
- Classes with one stable internal implementation.
- Premature abstraction without a second implementation, test need, or volatility point.
- Thin wrappers that merely rename another API without isolating coupling.

An interface should represent a capability, not just mirror a class.

## 5. Contract-Driven Execution

Define boundaries through contracts.

Do not model actions as a pile of concrete steps. Model them as contracts that must be satisfied.

Examples:

- "Implement status effects" -> define an `IStatusEffect` contract that applies effects without invading the host entity lifecycle.
- "Refactor inventory access" -> define an inventory capability interface that exposes only counting, storing, consuming, and slot-query operations required by the caller.
- "Refactor concurrent processing" -> encapsulate shared access behind channels, lock-free structures, actors, or explicit synchronization boundaries.
- "Add persistence" -> define repository or serializer contracts before binding domain objects to a database or file format.
- "Add UI preview" -> define a read-only preview model rather than letting UI compute domain rules.

Contracts should reduce knowledge, not increase ceremony.

## 6. Defensive Refactoring

Clean technical debt instead of routing around it.

Before adding new behavior, stop and propose a refactor if any of these appear:

- One class owns storage, validation, business rules, UI formatting, framework lookup, and mutation.
- UI directly mutates domain state.
- A method validates, simulates, mutates, emits notifications, and formats output at the same time.
- A component or service knows too many unrelated siblings.
- Adding one feature requires editing many unrelated classes.
- Runtime state is stored in static configuration or resource data.
- A global event bus is used where explicit dependencies, local signals, or scoped observers would be clearer.
- Framework APIs leak into pure rules.
- Tests require booting the full app, engine, server, scene tree, database, or runtime environment.

When direct implementation would make an existing class larger or more coupled, first extract an interface, service, adapter, or anti-corruption layer.

## 7. Anti-Corruption and Adapter Rule

When integrating with messy legacy code, unstable frameworks, external APIs, or poorly bounded systems, isolate the new logic behind an adapter or anti-corruption layer.

Use an adapter when:

- The external API exposes too much detail.
- Naming or data shape does not match the domain model.
- The dependency is hard to test.
- The external system is volatile.
- Direct dependency would pollute clean domain code.

The adapter may be ugly internally. The domain-facing contract must stay clean.

## 8. Anti-Overengineering Rule

Do not introduce a design pattern unless it removes real coupling, isolates a volatile rule, enables testing, or protects a meaningful boundary.

Avoid:

- Abstract factories for objects with only one implementation.
- Strategy interfaces for logic with no current or likely variation.
- Deep inheritance trees for domain entities.
- Event buses for simple parent-child or local communication.
- Global singletons for mutable application state.
- Generic managers that own unrelated systems.
- Excessive dependency injection for private, stable implementation details.
- Pattern stacking where simple composition would work.

Prefer the simplest boundary that preserves future extensibility.

Good architecture is not the maximum number of patterns. Good architecture isolates change.

## 9. Transaction and State Mutation Rule

For operations that remove, add, transfer, reserve, purchase, craft, equip, persist, or otherwise mutate important state, prefer a transaction-style flow.

Use this structure:

1. Validate inputs.
2. Build an operation plan.
3. Simulate against current state.
4. Verify constraints.
5. Commit changes.
6. Emit notifications or events after successful commit.

Avoid partially mutating state before all constraints are known.

When atomicity is required, do not perform:

```text
check -> mutate A -> mutate B -> discover failure
```

Prefer:

```text
check -> plan -> simulate -> commit A and B -> notify
```

If rollback is necessary, make it explicit.

## 10. Implementation Discipline

Reduce common LLM coding mistakes during implementation.

Before coding:

- State assumptions explicitly.
- Surface uncertainty instead of hiding it.
- If multiple interpretations exist, name them instead of silently choosing one.
- Prefer the simplest solution that satisfies the requested goal.
- Push back when the requested direction would create unnecessary complexity or coupling.
- Ask for clarification when the ambiguity blocks correctness.

When editing existing code:

- Make surgical changes.
- Touch only what is necessary for the requested task.
- Match the existing style unless the user asks for a broader refactor.
- Do not clean up unrelated code.
- Do not reformat unrelated sections.
- Do not introduce speculative features, configurability, or extensibility.
- Remove imports, variables, methods, or types only if your own changes made them unused.
- Mention pre-existing dead code or design smells, but do not delete them unless asked.

Every changed line should trace back to the user's request or to a refactor explicitly required by the architectural boundary.

## 11. Verification and Success Criteria

Turn implementation work into verifiable goals.

Before implementation, define success criteria when the task is non-trivial.

Examples:

- "Add validation" -> invalid inputs are rejected, valid inputs still pass, and tests or checks cover both paths.
- "Fix a bug" -> the bug is reproduced first when practical, then fixed, then verified.
- "Refactor a component" -> behavior is preserved before and after the refactor.
- "Add a new system" -> the system has a clear API, isolated state ownership, and a minimal usage example.

For multi-step tasks, use this compact plan format:

```text
1. Step -> verify: check
2. Step -> verify: check
3. Step -> verify: check
```

Prefer concrete verification:

- Unit tests.
- Type checks.
- Compile checks.
- Existing test suites.
- Minimal reproduction cases.
- Invariants.
- Before/after behavior comparisons.

Do not claim success without verification. If verification cannot be run, state what should be verified manually.

## 12. Pre-Code Checklist

Before writing implementation code, verify:

- Who owns the state?
- Who is allowed to mutate it?
- Is the mutation atomic?
- Can this logic be tested without the framework runtime?
- Does UI depend on behavior or only on a stable API?
- Does static data remain separate from runtime state?
- Is this abstraction justified by a real variation point?
- Is this interface hiding coupling or merely adding ceremony?
- Will this change make an existing class larger and less cohesive?
- Could a small adapter or service isolate the new behavior better?
- Is the chosen design appropriate for the domain: application logic, game logic, UI, data pipeline, backend, embedded, or systems-level code?

## 13. Output Expectations

When reviewing code:

- Identify the architectural smell before proposing code.
- Name the violated principle if one exists.
- Explain the smallest safe refactor.
- Provide code only after explaining the new boundary.
- Prefer concrete, compilable examples.
- Show where each class or interface belongs.
- Explain trade-offs and what should not be abstracted yet.

When designing a new system:

- Start with the domain model.
- Define contracts and ownership.
- Choose patterns only where they protect real variation points.
- Keep the first implementation minimal but not entangled.
- Provide a migration path from current code to target architecture.

When explaining code:

- Translate implementation into intent.
- Explain state flow, mutation flow, and dependency flow.
- Point out hidden assumptions.
- Suggest naming improvements when they clarify architecture.

## 14. Default Design Bias

Default toward:

- High cohesion.
- Low coupling.
- Explicit ownership.
- Small public APIs.
- Framework-independent core logic.
- Stable contracts at system boundaries.
- Composition over inheritance.
- Testable domain services.
- Atomic mutation flows.
- Clear separation between static data and runtime state.
- Domain-aware abstraction depth.

Reject:

- Spaghetti code.
- God objects.
- Hidden global mutable state.
- UI-driven business logic.
- Framework leakage into pure domain rules.
- Premature generalization.
- Overloaded managers.
- Pattern use without a concrete reason.
