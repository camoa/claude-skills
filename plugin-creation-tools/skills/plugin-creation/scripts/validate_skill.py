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


def main():
    if len(sys.argv) != 2:
        print("Usage: validate_skill.py <skill-directory>")
        print("\nExample:")
        print("  validate_skill.py ./my-skill")
        sys.exit(1)

    skill_path = sys.argv[1]
    print(f"🔍 Validating: {skill_path}\n")

    valid, messages = validate_skill(skill_path)

    # Print messages by level
    for level, msg in messages:
        if level == 'ERROR':
            print(f"❌ {msg}")
        elif level == 'WARN':
            print(f"⚠️  {msg}")
        else:
            print(f"ℹ️  {msg}")

    print()
    if valid:
        print("✅ Skill is valid!")
    else:
        print("❌ Validation failed - fix errors above")

    sys.exit(0 if valid else 1)


if __name__ == "__main__":
    main()
