# Guide Index (Fallback)

Use this keyword-to-URL mapping as a built-in fallback when `llms.hash` / `llms.txt` cannot be fetched.
When online, prefer the live `llms.txt` + topic `index.md` flow (includes disambiguation via guide-meta).

## Discovery

Index URL: `https://camoa.github.io/dev-guides/llms.txt`
Base URL: `https://camoa.github.io/dev-guides/`

## Drupal Guides

| Keywords | Topic URL | Slug |
|----------|-----------|------|
| form, validation, form alter, FAPI | `drupal/forms/` | drupal-forms |
| config form, settings form, ConfigFormBase | `drupal/config-forms/` | drupal-config-forms |
| entity, field, content type, bundle | `drupal/entities/` | drupal-entities |
| plugin, plugin type, annotation, attribute | `drupal/plugins/` | drupal-plugins |
| route, access, permission, controller | `drupal/routing/` | drupal-routing |
| service, dependency injection, container, autowire | `drupal/services/` | drupal-services |
| cache, cache tag, cache context, max-age, BigPipe | `drupal/caching/` | drupal-caching |
| config, config schema, Config Split, sync | `drupal/config-management/` | drupal-config-management |
| render, render array, #theme, #type, attachments | `drupal/render-api/` | drupal-render-api |
| security, XSS, CSRF, SQL injection, CSP | `drupal/security/` | drupal-security |
| SDC, component, single directory, *.component.yml | `drupal/sdc/` | drupal-sdc |
| JavaScript, behaviors, once, Drupal.ajax | `drupal/js-development/` | drupal-js-development |
| views, display, filter, relationship, argument | `drupal/views/` | drupal-views |
| block, block plugin, BlockBase, block_content | `drupal/blocks/` | drupal-blocks |
| layout builder, section, inline block, LB Styles | `drupal/layout-builder/` | drupal-layout-builder |
| migration, migrate, D7, source plugin, process | `drupal/migration/` | drupal-migration |
| recipe, config action, DefaultContent | `drupal/recipes/` | drupal-recipes |
| taxonomy, vocabulary, term, hierarchy | `drupal/taxonomy/` | drupal-taxonomy |
| media, media type, oembed, media library | `drupal/media/` | drupal-media |
| image style, responsive image, breakpoint | `drupal/image-styles/` | drupal-image-styles |
| test, PHPUnit, kernel test, browser test | `drupal/testing/` | drupal-testing |
| JSON:API, jsonapi, REST, decoupled | `drupal/jsonapi/` | drupal-jsonapi |
| icon, icon pack, IconFinder | `drupal/icon-api/` | drupal-icon-api |
| ECA, event condition action, workflow | `drupal/eca/` | drupal-eca |
| GitHub Actions, CI/CD, deployment | `drupal/github-actions/` | drupal-github-actions |
| AI, automator, assistant, chatbot | `drupal/ai-content/` | drupal-ai-content |
| custom field, compound field, FieldType | `drupal/custom-field/` | drupal-custom-field |
| Klaro, cookie consent, privacy | `drupal/klaro/` | drupal-klaro |
| UI Patterns, story.yml, prop, slot, mapping | `drupal/ui-patterns/` | drupal-ui-patterns |
| Storybook, stories.yml, component preview | `drupal/storybook/` | drupal-storybook |
| Twig, template, preprocess, twig_tweak | `drupal/twig-theming/` | drupal-twig-theming |
| multilingual, translation, i18n, TMGMT | `drupal/multilingual/` | drupal-multilingual |
| breadcrumb, trail, navigation | `drupal/breadcrumbs/` | drupal-breadcrumbs |
| Canvas, drawing, visual | `drupal/canvas/` | drupal-canvas |
| Salesforce, CRM, sync | `drupal/salesforce/` | drupal-salesforce |
| TDD, test-driven, Red-Green-Refactor (Drupal) | `drupal/tdd/` | drupal-tdd |
| SOLID, SRP, OCP, DIP (Drupal) | `drupal/solid/` | drupal-solid |
| DRY, duplication, reuse (Drupal) | `drupal/dry/` | drupal-dry |

## Next.js Guides

| Keywords | Topic URL | Slug |
|----------|-----------|------|
| Next.js, Next Drupal, decoupled, SSR | `nextjs/next-drupal/` | next-drupal |
| Tiptap, ProseMirror, rich text editor | `nextjs/tiptap-editor/` | tiptap-editor |
| DeepChat, chat component, streaming | `nextjs/deepchat-nextjs/` | deepchat-nextjs |

## Design System Guides

| Keywords | Topic URL | Slug |
|----------|-----------|------|
| design system recognition, element identification | `design-systems/recognition/` | design-system-recognition |
| Bootstrap, SCSS, Sass, mapping | `design-systems/bootstrap/` | design-system-bootstrap |
| Radix, sub-theme, SDC components | `design-systems/radix-sdc/` | design-system-radix-sdc |
| Radix components, catalog | `design-systems/radix-components/` | design-system-radix-components |
| Tailwind, tokens, DaisyUI, DTCG | `design-systems/tailwind-tokens/` | design-system-tailwind-tokens |
| JSX to Twig, React to Drupal | `design-systems/jsx-to-twig/` | design-system-jsx-to-twig |
| DaisyUI, UI Suite | `design-systems/daisyui/` | design-system-daisyui |

## Development Practice Guides

| Keywords | Topic URL | Slug |
|----------|-----------|------|
| SOLID, SRP, OCP, LSP, ISP, DIP (general) | `dev-practices/solid-principles/` | dev-solid-principles |
| DRY, duplication, Rule of Three (general) | `dev-practices/dry-principles/` | dev-dry-principles |
| TDD, spec-driven, test doubles (general) | `dev-practices/tdd-spec-driven/` | dev-tdd-spec-driven |
| security, OWASP, auth, API security (general) | `dev-practices/security-practices/` | dev-security-practices |
| CSS, modern CSS, container queries, @scope | `dev-practices/modern-css/` | modern-css |
| CSS Craft, motion, micro-interactions | `dev-practices/css-craft/` | css-craft |

## Disambiguation Quick Reference

| Term | Correct Guide | NOT This Guide |
|------|---------------|----------------|
| story.yml | drupal-ui-patterns | drupal-storybook |
| stories.yml | drupal-storybook | drupal-ui-patterns |
| inline blocks | drupal-layout-builder | drupal-blocks |
| block plugin, BlockBase | drupal-blocks | drupal-layout-builder |
| *.component.yml | drupal-sdc | drupal-ui-patterns |
| SOLID (Drupal context) | drupal-solid | dev-solid-principles |
| SOLID (general) | dev-solid-principles | drupal-solid |
| config entity | drupal-config-management | drupal-entities |
| content entity | drupal-entities | drupal-config-management |
| media library widget | drupal-media | drupal-image-styles |
| responsive image | drupal-image-styles | drupal-media |
