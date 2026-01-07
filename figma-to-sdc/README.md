# Figma to SDC

Convert Figma designs to Drupal components using AI-assisted analysis.

## Features

- **Figma Integration**: Extract component data from Figma via MCP
- **AI Analysis**: Automatically identify props, slots, and static elements
- **Dual Output**: Generate both SDC (Twig) and Canvas (JSX) components
- **Bootstrap Accommodation**: Apply 6px threshold framework for styling decisions
- **Interactive Review**: Confirm or modify AI suggestions before generation

## Installation

Add to your Claude Code configuration:

```json
{
  "plugins": [
    "camoa-skills/figma-to-sdc"
  ]
}
```

## Requirements

- Figma MCP server configured with API access
- For Canvas output: Drupal with Canvas module

## Usage

### Command (Explicit)

```
/figma-to-sdc <figma-url>
/figma-to-sdc <figma-url> --target canvas
/figma-to-sdc <figma-url> --target both --name my-component
```

### Skill (Automatic)

The skill triggers automatically when you:
- Provide a Figma URL and mention creating a component
- Ask to convert a design to Drupal
- Mention "Figma to SDC" or similar

## Workflow

1. **Input**: Provide Figma component URL
2. **Extract**: Fetch design data from Figma API
3. **Analyze**: AI categorizes elements as props/slots/static
4. **Review**: Confirm or adjust the analysis
5. **Generate**: Create component files
6. **Output**: Write to theme or output config YAML

## Output Formats

### SDC (Traditional)

```
components/component-name/
├── component-name.component.yml
├── component-name.twig
└── component-name.css
```

### Canvas (Drupal CMS)

```yaml
# js_component.component_name.yml
machineName: component_name
name: Component Name
props: { ... }
js: { original: '...', compiled: '' }
css: { original: '', compiled: '' }
```

## References

The skill includes detailed reference guides:

- `figma-extraction.md` - Figma API patterns
- `sdc-generation.md` - SDC file generation
- `canvas-generation.md` - Canvas/JSX patterns
- `bootstrap-accommodation.md` - 6px threshold framework
- `prop-type-mapping.md` - Figma to prop type mapping

## Related

- [Drupal SDC Documentation](https://www.drupal.org/docs/develop/theming-drupal/using-single-directory-components)
- [Canvas Module](https://www.drupal.org/project/canvas)
- [Figma API](https://www.figma.com/developers/api)

## License

MIT
