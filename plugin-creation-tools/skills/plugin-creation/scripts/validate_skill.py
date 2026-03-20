#!/usr/bin/env python3
"""
Skill Validator - Validates skill structure and content

Usage:
    validate_skill.py <skill-directory>

Example:
    validate_skill.py ./my-skill
"""

import sys
import re
from pathlib import Path

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


def validate_skill(skill_path):
    """
    Validate a skill directory.

    Args:
        skill_path: Path to skill directory

    Returns:
        Tuple of (is_valid, messages) where messages is list of (level, message)
    """
    skill_path = Path(skill_path).resolve()
    messages = []

    def error(msg):
        messages.append(('ERROR', msg))

    def warn(msg):
        messages.append(('WARN', msg))

    def info(msg):
        messages.append(('INFO', msg))

    # Check directory exists
    if not skill_path.exists():
        error(f"Directory not found: {skill_path}")
        return False, messages

    if not skill_path.is_dir():
        error(f"Path is not a directory: {skill_path}")
        return False, messages

    # Check SKILL.md exists
    skill_md = skill_path / 'SKILL.md'
    if not skill_md.exists():
        error("SKILL.md not found")
        return False, messages

    content = skill_md.read_text()

    # Check frontmatter exists
    if not content.startswith('---'):
        error("No YAML frontmatter (must start with ---)")
        return False, messages

    # Extract frontmatter
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        error("Invalid frontmatter format (missing closing ---)")
        return False, messages

    frontmatter_text = match.group(1)

    # Parse YAML
    if YAML_AVAILABLE:
        try:
            frontmatter = yaml.safe_load(frontmatter_text)
            if not isinstance(frontmatter, dict):
                error("Frontmatter must be a YAML dictionary")
                return False, messages
        except yaml.YAMLError as e:
            error(f"Invalid YAML: {e}")
            return False, messages
    else:
        # Basic parsing without yaml module
        frontmatter = {}
        for line in frontmatter_text.split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                frontmatter[key.strip()] = value.strip()

    # Check allowed properties
    ALLOWED = {'name', 'description', 'license', 'allowed-tools', 'metadata'}
    unexpected = set(frontmatter.keys()) - ALLOWED
    if unexpected:
        error(f"Unexpected frontmatter keys: {', '.join(sorted(unexpected))}")
        return False, messages

    # Validate name
    name = frontmatter.get('name', '')
    if not name:
        error("Missing 'name' in frontmatter")
        return False, messages

    if not isinstance(name, str):
        error(f"Name must be string, got {type(name).__name__}")
        return False, messages

    name = name.strip()
    if not re.match(r'^[a-z0-9-]+$', name):
        error(f"Name '{name}' must be hyphen-case (lowercase, digits, hyphens)")
        return False, messages

    if name.startswith('-') or name.endswith('-') or '--' in name:
        error(f"Name '{name}' has invalid hyphen usage")
        return False, messages

    if len(name) > 64:
        error(f"Name too long ({len(name)} chars, max 64)")
        return False, messages

    # Check name matches directory
    if name != skill_path.name:
        warn(f"Name '{name}' doesn't match directory '{skill_path.name}'")

    # Validate description
    description = frontmatter.get('description', '')
    if not description:
        error("Missing 'description' in frontmatter")
        return False, messages

    if not isinstance(description, str):
        error(f"Description must be string, got {type(description).__name__}")
        return False, messages

    description = description.strip()

    if '<' in description or '>' in description:
        error("Description cannot contain angle brackets")
        return False, messages

    if len(description) > 1024:
        error(f"Description too long ({len(description)} chars, max 1024)")
        return False, messages

    # Description quality checks (warnings)
    if not description.lower().startswith('use when'):
        warn("Description should start with 'Use when...'")

    if len(description) < 50:
        warn("Description seems short - include specific triggers")

    if 'you' in description.lower():
        warn("Description should use third person, not 'you'")

    # Check SKILL.md length
    body = content[match.end():].strip()
    line_count = len(body.split('\n'))
    if line_count > 500:
        warn(f"SKILL.md body is {line_count} lines (target: <500)")

    # Check for broken references
    refs = re.findall(r'references/([^\s\)]+)', content)
    for ref in refs:
        ref_path = skill_path / 'references' / ref
        if not ref_path.exists():
            warn(f"Referenced file not found: references/{ref}")

    # Check for broken script references
    scripts = re.findall(r'scripts/([^\s\)]+)', content)
    for script in scripts:
        script_path = skill_path / 'scripts' / script
        if not script_path.exists():
            warn(f"Referenced script not found: scripts/{script}")

    # Info about structure
    if (skill_path / 'scripts').exists():
        script_count = len(list((skill_path / 'scripts').glob('*.py')))
        info(f"Found {script_count} Python scripts")

    if (skill_path / 'references').exists():
        ref_count = len(list((skill_path / 'references').glob('*.md')))
        info(f"Found {ref_count} reference files")

    has_errors = any(level == 'ERROR' for level, _ in messages)
    return not has_errors, messages


def validate_marketplace(marketplace_path):
    """
    Validate a marketplace.json file.

    Args:
        marketplace_path: Path to marketplace.json file

    Returns:
        Tuple of (is_valid, messages) where messages is list of (level, message)
    """
    marketplace_path = Path(marketplace_path).resolve()
    messages = []

    def error(msg):
        messages.append(('ERROR', msg))

    def warn(msg):
        messages.append(('WARN', msg))

    def info(msg):
        messages.append(('INFO', msg))

    if not marketplace_path.exists():
        error(f"marketplace.json not found: {marketplace_path}")
        return False, messages

    # Parse JSON
    try:
        import json
        data = json.loads(marketplace_path.read_text())
    except Exception as e:
        error(f"Invalid JSON in marketplace.json: {e}")
        return False, messages

    # owner is required
    if not data.get('owner'):
        error("Missing 'owner' field in marketplace.json")

    # kebab-case name check
    name = data.get('name', '')
    if name and not re.match(r'^[a-z0-9-]+$', name):
        warn(f"Plugin name '{name}' is not kebab-case. Claude.ai marketplace sync requires kebab-case names.")

    # Reserved marketplace names
    RESERVED_NAMES = {
        'claude-code-marketplace', 'claude-code-plugins', 'claude-plugins-official',
        'anthropic-marketplace', 'anthropic-plugins', 'agent-skills',
        'life-sciences', 'knowledge-work-plugins',
    }
    if name in RESERVED_NAMES:
        error(f"Marketplace name '{name}' is reserved by Anthropic and cannot be used")

    # Plugin entry checks
    plugins = data.get('plugins', [])
    seen_names = set()
    for plugin in plugins:
        plugin_name = plugin.get('name', '')

        # Duplicate plugin names
        if plugin_name in seen_names:
            error(f"Duplicate plugin name '{plugin_name}' in marketplace.json")
        seen_names.add(plugin_name)

        source = plugin.get('source')
        if isinstance(source, dict):
            # "source" key is the discriminator, not "type"
            if 'type' in source and 'source' not in source:
                error(
                    f"Plugin '{plugin_name}': source object uses 'type' as discriminator key — "
                    f"use 'source' instead (e.g., {{\"source\": \"github\", ...}})"
                )
            # Path traversal check
            source_str = str(source)
            if '..' in source_str:
                error(f"Plugin '{plugin_name}': path traversal ('..') detected in source")
        elif isinstance(source, str):
            if '..' in source:
                error(f"Plugin '{plugin_name}': path traversal ('..') detected in source path '{source}'")

    has_errors = any(level == 'ERROR' for level, _ in messages)
    return not has_errors, messages


def validate_hooks(hooks_path):
    """
    Validate a hooks.json file.

    Args:
        hooks_path: Path to hooks.json file

    Returns:
        Tuple of (is_valid, messages) where messages is list of (level, message)
    """
    hooks_path = Path(hooks_path).resolve()
    messages = []

    def error(msg):
        messages.append(('ERROR', msg))

    if not hooks_path.exists():
        error(f"hooks.json not found: {hooks_path}")
        return False, messages

    try:
        import json
        data = json.loads(hooks_path.read_text())
    except Exception as e:
        error(f"Invalid JSON in hooks.json: {e}")
        return False, messages

    # Check for http hook type — only valid in settings.json, not hooks.json
    hooks_by_event = data.get('hooks', {})
    for event, matchers in hooks_by_event.items():
        if not isinstance(matchers, list):
            continue
        for matcher in matchers:
            for hook in matcher.get('hooks', []):
                if hook.get('type') == 'http':
                    error(
                        f"Event '{event}': 'http' hook type is not supported in hooks.json — "
                        f"http hooks only work in settings.json"
                    )

    has_errors = any(level == 'ERROR' for level, _ in messages)
    return not has_errors, messages


def _print_messages(messages):
    for level, msg in messages:
        if level == 'ERROR':
            print(f"❌ {msg}")
        elif level == 'WARN':
            print(f"⚠️  {msg}")
        else:
            print(f"ℹ️  {msg}")


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_skill.py <skill-directory>")
        print("       validate_skill.py --marketplace <marketplace.json>")
        print("       validate_skill.py --hooks <hooks.json>")
        print("\nExamples:")
        print("  validate_skill.py ./my-skill")
        print("  validate_skill.py --marketplace ./.claude-plugin/marketplace.json")
        print("  validate_skill.py --hooks ./hooks/hooks.json")
        sys.exit(1)

    if sys.argv[1] == '--marketplace' and len(sys.argv) == 3:
        target = sys.argv[2]
        print(f"🔍 Validating marketplace: {target}\n")
        valid, messages = validate_marketplace(target)
        _print_messages(messages)
        print()
        if valid:
            print("✅ marketplace.json is valid!")
        else:
            print("❌ Validation failed - fix errors above")
        sys.exit(0 if valid else 1)

    elif sys.argv[1] == '--hooks' and len(sys.argv) == 3:
        target = sys.argv[2]
        print(f"🔍 Validating hooks: {target}\n")
        valid, messages = validate_hooks(target)
        _print_messages(messages)
        print()
        if valid:
            print("✅ hooks.json is valid!")
        else:
            print("❌ Validation failed - fix errors above")
        sys.exit(0 if valid else 1)

    elif len(sys.argv) == 2:
        skill_path = sys.argv[1]
        print(f"🔍 Validating: {skill_path}\n")
        valid, messages = validate_skill(skill_path)
        _print_messages(messages)
        print()
        if valid:
            print("✅ Skill is valid!")
        else:
            print("❌ Validation failed - fix errors above")
        sys.exit(0 if valid else 1)

    else:
        print("Usage: validate_skill.py <skill-directory>")
        print("       validate_skill.py --marketplace <marketplace.json>")
        print("       validate_skill.py --hooks <hooks.json>")
        sys.exit(1)


if __name__ == "__main__":
    main()
