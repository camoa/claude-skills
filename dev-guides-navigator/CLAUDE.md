# Dev-Guides Navigator — Automatic Guide Usage

## Rule: Check Guides Before Design or Development Work

Before executing any design, architecture, or development task, check if a relevant guide exists:

1. Invoke the `dev-guides-navigator` skill with your task keywords
2. If a guide covers what you're about to do, **read it first**
3. Apply the guide's patterns and decisions to your work — do not just summarize

This applies to: Drupal development, theming, frontend/CSS, design systems, design-to-code conversion, Next.js, testing, security, architecture decisions, and any task where best practices matter.

## When to Check

- Creating or modifying Drupal modules, themes, or components
- Writing forms, entities, plugins, services, routing, or config
- Frontend work: CSS, SCSS, Bootstrap, Radix, SDC, Twig
- Design system work: analyzing designs, recognizing components, mapping to Bootstrap/Radix
- Converting designs to code: Figma-to-Drupal, JSX-to-Twig, Tailwind token extraction
- DaisyUI / UI Suite theming and component selection
- Architecture decisions (SOLID, DRY, TDD patterns)
- Security-sensitive code
- Next.js integration: next-drupal, DeepChat, Tiptap
- Any task where you're unsure of the correct pattern

## Fetching Rule

**Never use WebFetch for dev-guides.** Always use `curl -s` via Bash:
- `llms.hash` / `llms.txt` → `curl -s https://camoa.github.io/dev-guides/...`
- `index.md` / guides → `curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/{topic}/{file}.md`

WebFetch returns AI summaries or 400KB+ MkDocs HTML shells — neither is usable. Guides are atomic and fit in context via curl.

## When NOT to Check

- Simple file edits unrelated to development patterns
- Git operations, project management, or conversation
- Tasks where the user explicitly says to skip guides
