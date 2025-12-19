# Next.js Setup Operations

Setup and configuration operations for Next.js code quality tools.

## Contents

- [Operation 13: Setup Tools](#operation-13-setup-tools)

---

## Operation 13: Setup Tools

When user says "setup tools", "install ESLint" in a Next.js project:

Run `scripts/core/install-tools.sh` or manually install:

### 1. ESLint + Next.js Config
```bash
npm install -D eslint eslint-config-next @typescript-eslint/eslint-plugin \
    eslint-plugin-react-hooks eslint-config-prettier
```

### 2. ESLint Security Plugins (v1.8.0)
```bash
npm install -D eslint-plugin-security eslint-plugin-no-secrets
```

### 3. Jest + Testing Library
```bash
npm install -D jest @jest/globals jest-environment-jsdom \
    @testing-library/react @testing-library/jest-dom
```

### 4. Code Duplication Detection
```bash
npm install -D jscpd
```

### 5. Circular Dependency Detection
```bash
npm install -D madge
```

### 6. Cross-Stack Security Tools (v1.8.0)

See `scripts/core/install-tools.sh` or install manually:

```bash
# Semgrep (multi-language SAST)
pip3 install semgrep

# Trivy (dependency/secret scanner)
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Gitleaks (secret detection)
curl -sfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/scripts/install.sh | sh -s -- -b /usr/local/bin
```

### 7. Copy Templates (if needed)

- `templates/nextjs/eslint.config.js` - ESLint v9 flat config with TypeScript
- `templates/nextjs/jest.config.js` - Jest config with coverage thresholds
- `templates/nextjs/jest.setup.js` - Jest setup with Testing Library
- `templates/nextjs/.prettierrc` - Prettier config with Tailwind plugin
