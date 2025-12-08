#!/usr/bin/env python3
"""
Skill Initializer - Creates a new skill from template

Usage:
    init_skill.py <skill-name> --path <path>

Examples:
    init_skill.py my-new-skill --path ./skills
    init_skill.py pdf-processor --path ~/.claude/skills
"""

import sys
import re
from pathlib import Path


SKILL_TEMPLATE = """---
name: {skill_name}
description: Use when [specific triggers] - [what it does, third person]. Keywords: [relevant terms]
---

# {skill_title}

## Overview

[1-2 sentences explaining what this skill enables]

## When to Use

- [Specific trigger 1]
- [Specific trigger 2]
- NOT for: [anti-patterns]

## Core Pattern

[Essential technique or workflow - brief, scannable]

## Quick Reference

| Operation | How |
|-----------|-----|
| ... | ... |

## Implementation

[Step-by-step with brief examples. Reference files, don't reproduce code.]

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| ... | ... |

## See Also

- references/  (if detailed docs needed)
- scripts/     (if reusable code needed)
- assets/      (if templates/images needed)

---
Delete unused resource directories. Keep SKILL.md under 500 lines.
"""

EXAMPLE_SCRIPT = '''#!/usr/bin/env python3
"""
Example helper script for {skill_name}

Replace with actual implementation or delete if not needed.
Scripts are executed without loading into context - token efficient.
"""

import sys

def main():
    """Main entry point."""
    print(f"Running {skill_name} helper")
    # TODO: Add actual script logic
    # Examples: file processing, validation, automation

if __name__ == "__main__":
    main()
'''

EXAMPLE_REFERENCE = """# Reference: {skill_title}

Detailed documentation loaded on demand when Claude needs it.

## When to Use References

- Content too long for SKILL.md (>100 lines)
- Domain-specific details only needed sometimes
- Schemas, API docs, comprehensive guides

## Structure Tips

- Table of contents for files >100 lines
- Keep one level deep (no nested references)
- Include grep patterns for very large files (>10k words)

---
Delete this file if not needed. Only include essential references.
"""


def title_case_skill_name(skill_name):
    """Convert hyphenated skill name to Title Case."""
    return ' '.join(word.capitalize() for word in skill_name.split('-'))


def validate_skill_name(name):
    """Validate skill name follows conventions."""
    if not name:
        return False, "Name cannot be empty"
    if not re.match(r'^[a-z0-9-]+$', name):
        return False, "Name must be hyphen-case (lowercase letters, digits, hyphens only)"
    if name.startswith('-') or name.endswith('-') or '--' in name:
        return False, "Name cannot start/end with hyphen or have consecutive hyphens"
    if len(name) > 64:
        return False, f"Name too long ({len(name)} chars). Maximum is 64."
    return True, "Valid"


def init_skill(skill_name, path):
    """
    Initialize a new skill directory with template SKILL.md.

    Args:
        skill_name: Name of the skill (hyphen-case)
        path: Directory where skill folder should be created

    Returns:
        Path to created skill directory, or None if error
    """
    # Validate name
    valid, msg = validate_skill_name(skill_name)
    if not valid:
        print(f"❌ Invalid name: {msg}")
        return None

    skill_dir = Path(path).resolve() / skill_name

    if skill_dir.exists():
        print(f"❌ Directory already exists: {skill_dir}")
        return None

    try:
        skill_dir.mkdir(parents=True, exist_ok=False)
        print(f"✅ Created: {skill_dir}")
    except Exception as e:
        print(f"❌ Error creating directory: {e}")
        return None

    # Create SKILL.md
    skill_title = title_case_skill_name(skill_name)
    skill_content = SKILL_TEMPLATE.format(
        skill_name=skill_name,
        skill_title=skill_title
    )

    try:
        (skill_dir / 'SKILL.md').write_text(skill_content)
        print("✅ Created SKILL.md")
    except Exception as e:
        print(f"❌ Error creating SKILL.md: {e}")
        return None

    # Create resource directories with examples
    try:
        # scripts/
        scripts_dir = skill_dir / 'scripts'
        scripts_dir.mkdir()
        example_script = scripts_dir / 'example.py'
        example_script.write_text(EXAMPLE_SCRIPT.format(skill_name=skill_name))
        example_script.chmod(0o755)
        print("✅ Created scripts/example.py")

        # references/
        refs_dir = skill_dir / 'references'
        refs_dir.mkdir()
        (refs_dir / 'example.md').write_text(
            EXAMPLE_REFERENCE.format(skill_title=skill_title)
        )
        print("✅ Created references/example.md")

        # assets/ (empty, just directory)
        (skill_dir / 'assets').mkdir()
        print("✅ Created assets/")

    except Exception as e:
        print(f"❌ Error creating resources: {e}")
        return None

    print(f"\n✅ Skill '{skill_name}' initialized at {skill_dir}")
    print("\nNext steps:")
    print("1. Edit SKILL.md - complete description and content")
    print("2. Delete unused resource directories")
    print("3. Run validate_skill.py before packaging")
    print("4. Keep SKILL.md under 500 lines")

    return skill_dir


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--path':
        print("Usage: init_skill.py <skill-name> --path <path>")
        print("\nRequirements:")
        print("  - Hyphen-case (e.g., 'pdf-processor')")
        print("  - Lowercase letters, digits, hyphens only")
        print("  - Max 64 characters")
        print("\nExamples:")
        print("  init_skill.py my-skill --path ./skills")
        print("  init_skill.py data-analyzer --path ~/.claude/skills")
        sys.exit(1)

    skill_name = sys.argv[1]
    path = sys.argv[3]

    print(f"🚀 Initializing skill: {skill_name}")
    print(f"   Location: {path}\n")

    result = init_skill(skill_name, path)
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
