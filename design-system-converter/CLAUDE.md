# Design System Converter - Plugin Conventions

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity (sonnet for routing/analysis, opus for generation)
- Internal skills called only by commands should have `user-invocable: false`
- Body uses imperative voice -- instructions for Claude, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed
- Interactive commands use AskUserQuestion for user input

## External Guide Protocol
- WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover current guide pages
- WebFetch specific pages on demand as conversion progresses
- Never hardcode guide page URLs in skill instructions -- always discover via llms.txt

## General
- Current state only -- no historical narratives
- Reference files instead of reproducing content
- Flat `components/` directory for SDC (no atomic subdirectories)
- All SCSS must use Bootstrap variables -- never hardcode hex colors, font-family names, font-weight numbers, or transition durations
