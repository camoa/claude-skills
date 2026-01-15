---
description: Convert a Figma component to Drupal SDC or Canvas component
allowed-tools:
  - mcp__figma-mcp__get_figma_data
  - mcp__figma-mcp__download_figma_images
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
argument-hint: <figma-url> [--target sdc|canvas|both] [--name component-name]
---

# Figma to SDC Conversion

Convert the provided Figma component to a Drupal component.

## Arguments

- `$1` or `$ARGUMENTS`: Figma component URL
- `--target`: Output format (sdc, canvas, or both) - default: sdc
- `--name`: Component name override

## Process

1. **Parse the Figma URL** from `$ARGUMENTS`
   - Extract fileKey and nodeId
   - If no URL provided, ask user

2. **Determine target format**
   - Check for --target flag
   - Default to SDC if not specified
   - Ask user to confirm

3. **Get component name**
   - Check for --name flag
   - Otherwise derive from Figma component name
   - Ask user to confirm/rename

4. **Load the converting-figma-to-sdc skill** for the conversion workflow

5. **Execute the workflow**:
   - Extract Figma data
   - Analyze and categorize elements
   - Present analysis for review
   - Generate component files
   - Write to appropriate location

## Example Usage

```
/figma-to-sdc https://www.figma.com/design/abc123/MyDesign?node-id=1:234
/figma-to-sdc https://figma.com/file/xyz/File?node-id=5:67 --target canvas
/figma-to-sdc [url] --target both --name hero-banner
```

## Output Locations

**For SDC:**
Ask user for theme location, default to: `themes/custom/[theme]/components/[name]/`

**For Canvas:**
Output config YAML to: `config/install/js_component.[name].yml`
