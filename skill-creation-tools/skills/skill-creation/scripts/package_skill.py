#!/usr/bin/env python3
"""
Skill Packager - Creates a distributable .skill file

Usage:
    package_skill.py <skill-directory> [output-directory]

Example:
    package_skill.py ./my-skill
    package_skill.py ./my-skill ./dist
"""

import sys
import zipfile
from pathlib import Path

# Import validate_skill from same directory
try:
    from validate_skill import validate_skill
except ImportError:
    # Fallback if running from different directory
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "validate_skill",
        Path(__file__).parent / "validate_skill.py"
    )
    validate_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validate_module)
    validate_skill = validate_module.validate_skill


def package_skill(skill_path, output_dir=None):
    """
    Package a skill folder into a .skill file.

    Args:
        skill_path: Path to skill directory
        output_dir: Output directory (default: current directory)

    Returns:
        Path to created .skill file, or None if error
    """
    skill_path = Path(skill_path).resolve()

    if not skill_path.exists():
        print(f"❌ Skill folder not found: {skill_path}")
        return None

    if not skill_path.is_dir():
        print(f"❌ Not a directory: {skill_path}")
        return None

    if not (skill_path / 'SKILL.md').exists():
        print(f"❌ SKILL.md not found in {skill_path}")
        return None

    # Validate before packaging
    print("🔍 Validating skill...\n")
    valid, messages = validate_skill(skill_path)

    for level, msg in messages:
        if level == 'ERROR':
            print(f"❌ {msg}")
        elif level == 'WARN':
            print(f"⚠️  {msg}")

    if not valid:
        print("\n❌ Fix validation errors before packaging")
        return None

    print("\n✅ Validation passed\n")

    # Determine output path
    skill_name = skill_path.name
    if output_dir:
        output_path = Path(output_dir).resolve()
        output_path.mkdir(parents=True, exist_ok=True)
    else:
        output_path = Path.cwd()

    skill_file = output_path / f"{skill_name}.skill"

    # Files/directories to exclude
    EXCLUDE = {'.git', '.DS_Store', '__pycache__', '*.pyc', '.gitignore'}

    def should_exclude(path):
        name = path.name
        for pattern in EXCLUDE:
            if pattern.startswith('*'):
                if name.endswith(pattern[1:]):
                    return True
            elif name == pattern:
                return True
        return False

    # Create .skill file (zip format)
    try:
        with zipfile.ZipFile(skill_file, 'w', zipfile.ZIP_DEFLATED) as zipf:
            file_count = 0
            for file_path in skill_path.rglob('*'):
                if file_path.is_file() and not should_exclude(file_path):
                    # Skip if any parent is excluded
                    if any(should_exclude(p) for p in file_path.parents):
                        continue

                    arcname = file_path.relative_to(skill_path.parent)
                    zipf.write(file_path, arcname)
                    print(f"  📄 {arcname}")
                    file_count += 1

        print(f"\n✅ Packaged {file_count} files to: {skill_file}")
        print(f"   Size: {skill_file.stat().st_size / 1024:.1f} KB")
        return skill_file

    except Exception as e:
        print(f"❌ Error creating package: {e}")
        return None


def main():
    if len(sys.argv) < 2:
        print("Usage: package_skill.py <skill-directory> [output-directory]")
        print("\nCreates a .skill file (zip format) for distribution.")
        print("\nExamples:")
        print("  package_skill.py ./my-skill")
        print("  package_skill.py ./my-skill ./dist")
        sys.exit(1)

    skill_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"📦 Packaging: {skill_path}")
    if output_dir:
        print(f"   Output: {output_dir}")
    print()

    result = package_skill(skill_path, output_dir)
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
