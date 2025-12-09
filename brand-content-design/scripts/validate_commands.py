#!/usr/bin/env python3
"""
Command Integrity Validator for brand-content-design plugin.

Validates:
1. Frontmatter structure (description, allowed-tools)
2. AskUserQuestion compliance (2-4 options per question)
3. Skill references (visual-content, pptx, pdf)
4. File references exist
5. Step numbering consistency
6. Required sections present
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Tuple

# Colors for terminal output
RED = '\033[91m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

class CommandValidator:
    def __init__(self, commands_dir: str, references_dir: str):
        self.commands_dir = Path(commands_dir)
        self.references_dir = Path(references_dir)
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.passed: List[str] = []

    def validate_all(self) -> bool:
        """Validate all command files."""
        print(f"\n{BLUE}═══════════════════════════════════════════════════════════{RESET}")
        print(f"{BLUE}  Command Integrity Validator - brand-content-design{RESET}")
        print(f"{BLUE}═══════════════════════════════════════════════════════════{RESET}\n")

        command_files = list(self.commands_dir.glob("*.md"))

        for cmd_file in sorted(command_files):
            self.validate_command(cmd_file)

        self.print_summary()
        return len(self.errors) == 0

    def validate_command(self, filepath: Path):
        """Validate a single command file."""
        print(f"\n{BLUE}Validating:{RESET} {filepath.name}")

        with open(filepath, 'r') as f:
            content = f.read()

        # Run all validations
        self.check_frontmatter(filepath.name, content)
        self.check_askuserquestion(filepath.name, content)
        self.check_skill_references(filepath.name, content)
        self.check_file_references(filepath.name, content)
        self.check_step_numbering(filepath.name, content)
        self.check_required_sections(filepath.name, content)
        self.check_project_path_usage(filepath.name, content)

    def check_frontmatter(self, filename: str, content: str):
        """Check frontmatter structure."""
        # Check for frontmatter
        if not content.startswith('---'):
            self.errors.append(f"{filename}: Missing frontmatter (must start with ---)")
            return

        # Extract frontmatter
        match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
        if not match:
            self.errors.append(f"{filename}: Invalid frontmatter format")
            return

        frontmatter = match.group(1)

        # Check description
        if 'description:' not in frontmatter:
            self.errors.append(f"{filename}: Missing 'description' in frontmatter")
        else:
            self.passed.append(f"{filename}: Has description")

        # Check allowed-tools
        if 'allowed-tools:' not in frontmatter:
            self.warnings.append(f"{filename}: Missing 'allowed-tools' in frontmatter")
        else:
            self.passed.append(f"{filename}: Has allowed-tools")

    def check_askuserquestion(self, filename: str, content: str):
        """Check AskUserQuestion compliance (2-4 options)."""
        # Find all AskUserQuestion blocks
        auq_pattern = r'Use AskUserQuestion.*?(?=\n\n|\n\d+\.|\n\*\*|\Z)'
        matches = re.findall(auq_pattern, content, re.DOTALL | re.IGNORECASE)

        for i, match in enumerate(matches):
            # Count options (lines starting with -)
            options = re.findall(r'^\s*-\s*\*\*[^*]+\*\*', match, re.MULTILINE)
            option_count = len(options)

            if option_count > 0:
                if option_count < 2:
                    self.errors.append(f"{filename}: AskUserQuestion #{i+1} has {option_count} options (min 2)")
                elif option_count > 4:
                    self.errors.append(f"{filename}: AskUserQuestion #{i+1} has {option_count} options (max 4)")
                else:
                    self.passed.append(f"{filename}: AskUserQuestion #{i+1} has {option_count} options ✓")

        # Check for Header field
        header_count = len(re.findall(r'Header:\s*"[^"]*"', content))
        auq_count = len(re.findall(r'Use AskUserQuestion', content, re.IGNORECASE))

        if auq_count > 0 and header_count < auq_count:
            self.warnings.append(f"{filename}: Some AskUserQuestion blocks may be missing Header field")

    def check_skill_references(self, filename: str, content: str):
        """Check that skill references are correct."""
        # Check for old canvas-design reference
        if 'canvas-design' in content.lower() and 'visual-content' not in content.lower():
            self.errors.append(f"{filename}: References 'canvas-design' instead of 'visual-content'")

        # Check visual-content reference in content-creating commands
        content_commands = ['presentation.md', 'presentation-quick.md', 'carousel.md',
                          'carousel-quick.md', 'template-presentation.md', 'template-carousel.md']

        if filename in content_commands:
            if 'visual-content' not in content:
                self.errors.append(f"{filename}: Missing 'visual-content' skill reference")
            else:
                self.passed.append(f"{filename}: References visual-content skill ✓")

            # Check for style-constraints reference
            if 'style-constraints' not in content:
                self.warnings.append(f"{filename}: Missing 'style-constraints.md' reference")

    def check_file_references(self, filename: str, content: str):
        """Check that referenced files exist."""
        # Find references to references/ files
        ref_pattern = r'references/([a-z-]+\.md)'
        refs = re.findall(ref_pattern, content)

        for ref in refs:
            ref_path = self.references_dir / ref
            if not ref_path.exists():
                self.errors.append(f"{filename}: References non-existent file 'references/{ref}'")
            else:
                self.passed.append(f"{filename}: Reference 'references/{ref}' exists ✓")

    def check_step_numbering(self, filename: str, content: str):
        """Check step numbering is sequential."""
        # Find all step numbers
        steps = re.findall(r'^(\d+)\.\s+\*\*', content, re.MULTILINE)

        if steps:
            steps = [int(s) for s in steps]
            expected = 1
            for step in steps:
                if step != expected:
                    # Allow for substeps like 4a, 4b which reset to next number
                    if step != expected and step != expected + 1:
                        self.warnings.append(f"{filename}: Step numbering jumps from {expected-1} to {step}")
                expected = step + 1

            self.passed.append(f"{filename}: Has {len(steps)} numbered steps")

    def check_required_sections(self, filename: str, content: str):
        """Check for required sections based on command type."""
        # All commands should have Workflow
        if '## Workflow' not in content:
            self.errors.append(f"{filename}: Missing '## Workflow' section")
        else:
            self.passed.append(f"{filename}: Has Workflow section ✓")

        # All commands should have Output
        if '## Output' not in content:
            self.warnings.append(f"{filename}: Missing '## Output' section")
        else:
            self.passed.append(f"{filename}: Has Output section ✓")

        # Template commands should have Prerequisites
        if 'template-' in filename or filename in ['presentation.md', 'carousel.md']:
            if '## Prerequisites' not in content:
                self.warnings.append(f"{filename}: Missing '## Prerequisites' section")

    def check_project_path_usage(self, filename: str, content: str):
        """Check PROJECT_PATH is defined before use."""
        # Commands that need PROJECT_PATH
        project_commands = ['template-presentation.md', 'template-carousel.md',
                          'presentation.md', 'presentation-quick.md',
                          'carousel.md', 'carousel-quick.md',
                          'brand-extract.md', 'brand-palette.md']

        if filename in project_commands:
            if 'PROJECT_PATH' in content:
                # Check it's defined in step 1
                if 'Set PROJECT_PATH' in content or 'PROJECT_PATH' in content[:2000]:
                    self.passed.append(f"{filename}: PROJECT_PATH defined early ✓")
                else:
                    self.warnings.append(f"{filename}: PROJECT_PATH used but may not be defined early")

    def print_summary(self):
        """Print validation summary."""
        print(f"\n{BLUE}═══════════════════════════════════════════════════════════{RESET}")
        print(f"{BLUE}  Validation Summary{RESET}")
        print(f"{BLUE}═══════════════════════════════════════════════════════════{RESET}\n")

        if self.errors:
            print(f"{RED}ERRORS ({len(self.errors)}):{RESET}")
            for error in self.errors:
                print(f"  {RED}✗{RESET} {error}")
            print()

        if self.warnings:
            print(f"{YELLOW}WARNINGS ({len(self.warnings)}):{RESET}")
            for warning in self.warnings:
                print(f"  {YELLOW}⚠{RESET} {warning}")
            print()

        print(f"{GREEN}PASSED ({len(self.passed)}):{RESET}")
        # Group by file for cleaner output
        passed_by_file: Dict[str, List[str]] = {}
        for p in self.passed:
            file = p.split(':')[0]
            if file not in passed_by_file:
                passed_by_file[file] = []
            passed_by_file[file].append(p.split(': ', 1)[1])

        for file, checks in sorted(passed_by_file.items()):
            print(f"  {GREEN}✓{RESET} {file}: {len(checks)} checks passed")

        print(f"\n{BLUE}───────────────────────────────────────────────────────────{RESET}")
        total = len(self.errors) + len(self.warnings) + len(self.passed)
        print(f"  Total checks: {total}")
        print(f"  {RED}Errors: {len(self.errors)}{RESET}")
        print(f"  {YELLOW}Warnings: {len(self.warnings)}{RESET}")
        print(f"  {GREEN}Passed: {len(self.passed)}{RESET}")
        print(f"{BLUE}───────────────────────────────────────────────────────────{RESET}\n")

        if self.errors:
            print(f"{RED}VALIDATION FAILED{RESET}")
            return False
        elif self.warnings:
            print(f"{YELLOW}VALIDATION PASSED WITH WARNINGS{RESET}")
            return True
        else:
            print(f"{GREEN}VALIDATION PASSED{RESET}")
            return True


def main():
    # Determine paths relative to script location
    script_dir = Path(__file__).parent
    plugin_dir = script_dir.parent

    commands_dir = plugin_dir / "commands"
    references_dir = plugin_dir / "skills" / "brand-content-design" / "references"

    if not commands_dir.exists():
        print(f"{RED}Error: Commands directory not found: {commands_dir}{RESET}")
        sys.exit(1)

    if not references_dir.exists():
        print(f"{YELLOW}Warning: References directory not found: {references_dir}{RESET}")

    validator = CommandValidator(str(commands_dir), str(references_dir))
    success = validator.validate_all()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
