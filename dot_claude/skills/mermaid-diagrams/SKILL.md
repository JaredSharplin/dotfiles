---
name: mermaid-diagrams
description: Write clear, readable Mermaid diagrams for GitHub PRs and documentation. Use when creating architecture diagrams, before/after comparisons, dependency graphs, or any Mermaid diagram in a PR body or markdown file. Triggers include "mermaid", "diagram", "architecture diagram", "dependency graph", "before/after diagram".
---

# Mermaid Diagrams for GitHub

## GitHub Renderer Constraints

GitHub uses a strict Mermaid parser. These rules prevent silent render failures:

- **No HTML in node labels** — use ` — ` instead of `<br/>`
- **No unlabelled dotted arrows** — `-.->|label| B` not `-.-> B`
- **Define nodes before edges** — declare all nodes first, then draw connections
- **Use `-->|label|` syntax** — not `-- "label" -->` (fragile on GitHub)
- **No special characters in labels** — avoid unescaped `()`, `<>`, `{}` inside quoted strings

## Layout

- **`graph TD` (top-down)** for hierarchies — callers at top, callees at bottom
- **`graph LR` (left-right)** only for sequential flows or timelines
- **Avoid subgraphs unless essential** — they force side-by-side layout and spread diagrams horizontally
- **Short node labels** — strip shared prefixes (e.g. `compose` not `communication--compose`)
- **Role or size as subtitle** — `["compose (250 lines)"]` or `["messages — list only"]`

## Node Shapes

```
node["Standard box"]        — controllers, modules
node{{"Hexagon"}}           — shared resources, key concepts
node(["Stadium/pill"])       — external systems
node[("Database")]           — data stores
```

## Edges

- Label with **what is communicated**: `-->|insertAtCursor|`
- Solid arrows (`-->`) for direct calls
- Dotted arrows (`-.->`) for loose coupling (events, data-actions)
- Keep labels short — method names or role descriptions, not sentences

## Colour

```
classDef problem fill:#dc2626,color:#fff,stroke:#dc2626
classDef warning fill:#f59e0b,color:#000,stroke:#f59e0b
classDef owner fill:#2563eb,color:#fff,stroke:#2563eb
classDef clean fill:#16a34a,color:#fff,stroke:#16a34a
classDef neutral fill:#6b7280,color:#fff,stroke:#6b7280
```

2-3 highlighted nodes max. Everything else stays default.

## Before/After Comparisons

Wrap each in a collapsible `<details>` block. Add 1-2 sentences of prose above each diagram explaining what to look for. Make the problem visually obvious in "before" (red) and the improvement obvious in "after" (blue/green).

```markdown
<details>
<summary>Before — [problem statement]</summary>

[1-2 sentence explanation]

` ` `mermaid
graph TD
    ...
` ` `

</details>

<details>
<summary>After — [solution statement]</summary>

[1-2 sentence explanation]

` ` `mermaid
graph TD
    ...
` ` `

</details>
```

## Audience

Write for someone unfamiliar with the codebase. Each diagram should answer:

- **What is the system?** (node labels with roles)
- **How do components talk?** (edge labels with method names)
- **What is the problem or improvement?** (colour)

Prefer plain language in labels — "owns" over "target", "calls" over "outlet".
