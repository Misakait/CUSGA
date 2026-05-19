---
name: architectural-engineering-guidelines
description: Behavioral guidelines for architectural software engineering. Use to enforce SOLID principles, design patterns, high cohesion, and low coupling, while adapting abstractions to specific domain constraints.
---

# Architectural Engineering Guidelines

**核心原则**：在动手写代码前确立架构边界。拒绝为了快速实现而堆砌面条代码（Spaghetti Code），一切修改必须向高内聚、低耦合的系统演进。

## 1. 架构推演先行 (Architecture Before Implementation)

**不要盲目填补逻辑。先建立抽象模型。**

- 明确指出当前代码涉及的核心实体（Entities）及其边界。
- 在动手编码前，必须声明打算采用的设计模式（例如：处理状态异常的状态模式、处理物品栏和战斗计算的策略模式、处理系统级解耦的观察者模式），并简述“为什么它最适合当前场景”。
- 如果发现现有代码严重违反单一职责原则（SRP）或开闭原则（OCP），必须明确指出，并优先提供解耦的接口级重构方案。

## 2. 领域自适应的抽象 (Domain-Aware Abstraction)

**根据运行环境决定抽象的深度，拒绝一刀切的过度设计。**

- **业务与应用层**（如利用虚拟线程的高并发后端、游戏逻辑引擎）：强制使用接口隔离、依赖注入和多态。将数据状态与行为逻辑严格分离，确保各个子模块独立测试、互不干扰。
- **底层与系统层**（如裸机内核开发、页表管理与异常中断处理）：立刻收敛面向对象思维。在此场景下，优先考虑数据局部性（Data Locality）、零成本抽象和内存安全。用严格的生命周期控制、枚举状态机和连续内存结构代替深层继承与虚函数表。

## 3. 防御性重构 (Defensive Refactoring)

**清理技术债，而不是绕过它。**

- 当要求添加新功能时，如果发现直接硬编码会导致原有类膨胀或引入新的强耦合，**停止编写业务代码**。首先输出一个将原有逻辑抽取为独立接口/组件的重构路径。
- 绝不在现有的乱局中打补丁。通过建立防腐层（Anti-Corruption Layer）或适配器（Adapter），将新逻辑干净地隔离在外。

## 4. 契约驱动设计 (Contract-Driven Execution)

**用接口契约定义边界。**

- 动作不应该是具体的步骤，而应该是契约的达成。
- 例如：“实现状态效果” → “定义 IStatusEffect 接口，确保增益/减益逻辑对宿主实体的生命周期是无侵入的。”
- 例如：“重构并发模型” → “确保共享资源的访问被封装在无锁数据结构或安全的通道（Channel）中，暴露的只有纯函数接口。”
