# Examples

Worked examples of routing a user request to the correct guide. The routing
method itself is in `SKILL.md`.

| User says | Action |
|-----------|--------|
| "I need to create a Drupal form" | Match "form" → `drupal/forms/` → fetch index.md → pick guide for form creation |
| "Add a story.yml for my component" | Match "story.yml" → check guide-meta → `drupal/ui-patterns/` (NOT storybook) |
| "Set up responsive images" | Match "responsive image" → `drupal/image-styles/` (NOT drupal/media) |
| "How do I use Config Split?" | Match "Config Split" → `drupal/config-management/` |
| "I need SOLID architecture for my module" | Drupal context → `drupal/solid-principles/` (NOT generic `development/solid-principles`) |
| "Build a FormBase vs ConfigFormBase" | index.md routing table has both → read Summary column → FormBase Summary mentions entity forms, ConfigFormBase mentions config → pick based on user context |
