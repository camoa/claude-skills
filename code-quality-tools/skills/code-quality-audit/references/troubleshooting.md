# Troubleshooting Guide

Common issues and solutions for code-quality-tools plugin.

## Installation Issues

### "Command not found: ddev" (Drupal)

**Cause:** DDEV not installed or not in PATH

**Solution:**
1. Install DDEV: https://ddev.readthedocs.io/en/stable/users/install/
2. Verify: `ddev --version`
3. Restart terminal

### "Command not found: npm" (Next.js)

**Cause:** Node.js not installed

**Solution:**
1. Install Node.js 18+: https://nodejs.org/
2. Verify: `node --version && npm --version`
3. Restart terminal

### "Command not found: semgrep/trivy/gitleaks"

**Cause:** System tools not installed

**Solution:**
- **Semgrep**: `pip install semgrep` or `brew install semgrep`
- **Trivy**: https://trivy.dev/latest/getting-started/installation/
- **Gitleaks**: https://github.com/gitleaks/gitleaks#installing

## Runtime Issues

### "DDEV is not running"

**Cause:** DDEV container stopped

**Solution:**
```bash
ddev start
ddev status  # Verify running
```

### "PHP version mismatch"

**Cause:** Tool requires PHP 8.1+ but project uses 8.0

**Solution:**
1. Edit `.ddev/config.yaml`:
   ```yaml
   php_version: "8.2"
   ```
2. Restart: `ddev restart`

### "Out of memory"

**Cause:** PHPStan/analysis tools need more memory

**Solution:**

**Option 1 - Increase PHP memory:**
```bash
# .ddev/php/my-php.ini
memory_limit = 512M
```

**Option 2 - Exclude directories:**
```bash
# phpstan.neon
parameters:
  excludePaths:
    - vendor/
    - web/core/
```

**Option 3 - Run smaller checks:**
```bash
/code-quality:lint      # Just linting
/code-quality:security  # Just security
```

### "Permission denied"

**Cause:** Script not executable or file permissions issue

**Solution:**
```bash
chmod +x scripts/core/*.sh
chmod +x scripts/drupal/*.sh
chmod +x scripts/nextjs/*.sh
```

## Test Issues

### "No tests found"

**Cause:** Tests don't match naming convention or path

**Solution:**

**Drupal:**
- Tests must be in `tests/src/` directory
- File names: `*Test.php`
- Check `phpunit.xml` configuration

**Next.js:**
- Tests must match: `*.test.js`, `*.test.tsx`, `*.spec.js`
- Check `jest.config.js` configuration

### "Coverage tool not found"

**Cause:** Coverage extensions not installed

**Solution:**

**Drupal:**
```bash
ddev composer require --dev phpunit/php-code-coverage
# PCOV already included in DDEV
```

**Next.js:**
```bash
npm install --save-dev @testing-library/jest-dom
```

## Security Scan Issues

### "Too many security findings"

**Cause:** First scan often finds many issues

**Solution:**
1. Review `.reports/security.json` for details
2. Prioritize critical/high severity first
3. Filter by severity:
   ```json
   // .code-quality.json (create if needed)
   {
     "thresholds": {
       "security_severity": "high"
     }
   }
   ```

### "False positives in security scan"

**Cause:** Static analysis can flag safe code

**Solution:**
1. Review finding context in code
2. Add suppressions if truly false positive:

   **PHPStan:**
   ```php
   /** @phpstan-ignore-next-line */
   ```

   **Semgrep:**
   ```yaml
   # .semgrep.yml
   rules:
     - id: false-positive-rule
       severity: WARNING
   ```

## Performance Issues

### "Audit takes too long"

**Cause:** Large codebase or slow tools

**Solution:**
1. Run specific checks instead of full audit:
   ```bash
   /code-quality:lint      # Fast
   /code-quality:coverage  # Medium
   /code-quality:security  # Slow
   ```

2. Exclude directories (phpstan.neon, .eslintignore):
   ```
   vendor/
   node_modules/
   web/core/
   ```

3. Use incremental analysis (PHPStan):
   ```neon
   # phpstan.neon
   parameters:
     tmpDir: .phpstan-cache
   ```

## Git Hooks Issues

### "Pre-commit hook too slow"

**Cause:** Running too many checks

**Solution:**

**GrumPHP (Drupal)** - Edit `grumphp.yml`:
```yaml
grumphp:
  testsuites:
    git_pre_commit:
      tasks:
        - phpcs  # Just standards, not full PHPStan
```

**Husky (Next.js)** - Edit `package.json`:
```json
"lint-staged": {
  "*.{js,jsx,ts,tsx}": [
    "eslint --fix"
    // Remove: "jest --findRelatedTests"
  ]
}
```

### "Can't commit - hook blocks me"

**Cause:** Quality checks failing

**Solution:**

**Option 1 - Fix issues:**
```bash
/code-quality:lint   # See what's failing
```

**Option 2 - Skip hooks (use sparingly):**
```bash
git commit --no-verify -m "WIP"
```

**Option 3 - Disable hooks:**
```json
// .code-quality.json
{
  "git_hooks": {
    "enabled": false
  }
}
```

## Platform-Specific Issues

### macOS

**Issue:** "xcrun: error: invalid active developer path"

**Solution:**
```bash
xcode-select --install
```

### Linux

**Issue:** "docker: permission denied"

**Solution:**
```bash
sudo usermod -aG docker $USER
newgrp docker  # Or logout/login
```

### Windows (WSL2)

**Issue:** Line ending problems (CRLF vs LF)

**Solution:**
```bash
git config --global core.autocrlf input
```

## Still Having Issues?

1. **Check versions:**
   ```bash
   ddev --version
   php --version
   node --version
   semgrep --version
   ```

2. **Enable debug mode:**
   ```bash
   # Add to commands:
   set -x  # Bash debug mode
   ```

3. **Check logs:**
   ```bash
   ddev logs  # Drupal
   npm run test -- --verbose  # Next.js
   ```

4. **GitHub Issues:** https://github.com/camoa/claude-skills/issues

5. **Ask Claude:** Describe the error and ask for help - Claude can read this guide and provide context-specific solutions.
