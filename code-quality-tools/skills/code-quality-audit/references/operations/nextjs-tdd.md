# Next.js TDD Workflow

Test-Driven Development workflow for Next.js projects.

## Contents

- [Overview](#overview)
- [TDD Phases](#tdd-phases)
- [Watch Mode](#watch-mode)
- [Cycle Targets](#cycle-targets)

---

## Overview

When user says "start TDD", "jest watch" in a Next.js project:

**Key Principle:** Write the test FIRST, watch it FAIL, then write minimal code to PASS.

---

## TDD Phases

Run `scripts/nextjs/tdd-workflow.sh` with phases:

### RED Phase (Test Must Fail)

```bash
scripts/nextjs/tdd-workflow.sh red [test-file]
```

1. Write a failing test
2. Run the test - **it must fail**
3. If test passes, warn: "In RED phase, test should fail first"

**Example:**
```typescript
// button.test.tsx
import { render, screen } from '@testing-library/react';
import { Button } from './button';

describe('Button', () => {
  it('should render with text', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByText('Click me')).toBeInTheDocument();
  });
});
```

### GREEN Phase (Minimal Code to Pass)

```bash
scripts/nextjs/tdd-workflow.sh green [test-file]
```

1. Write **only enough code** to make the test pass
2. Don't optimize yet
3. Run test - it must pass

**Example:**
```typescript
// button.tsx
export function Button({ children }: { children: React.ReactNode }) {
  return <button>{children}</button>;
}
```

### REFACTOR Phase (Clean Up, Stay Green)

```bash
scripts/nextjs/tdd-workflow.sh refactor [test-file]
```

1. Improve naming, extract components
2. Tests must stay green
3. Don't add functionality

**Example:**
```typescript
// button.tsx
interface ButtonProps {
  children: React.ReactNode;
  variant?: 'primary' | 'secondary';
}

export function Button({ children, variant = 'primary' }: ButtonProps) {
  const className = variant === 'primary' ? 'btn-primary' : 'btn-secondary';
  return <button className={className}>{children}</button>;
}
```

---

## Watch Mode

For continuous TDD:

```bash
scripts/nextjs/tdd-workflow.sh watch
# or: npx jest --watch
```

Watches for file changes and reruns tests automatically.

**Jest Interactive Commands:**
- `p` - Filter by filename pattern
- `t` - Filter by test name pattern
- `a` - Run all tests
- `q` - Quit watch mode

---

## Cycle Targets

**Target:** 20-40 cycles/hour during active TDD

**A cycle is:** RED → GREEN → REFACTOR → commit

**Too slow (<10/hour)?**
- Tests too large (split into smaller tests)
- Too much code per cycle (write less code)
- Not using watch mode

**Too fast (>50/hour)?**
- Tests too trivial (increase test quality)
- Skipping REFACTOR phase (maintain code quality)

---

## Testing Patterns

### Component Tests
```typescript
import { render, screen, fireEvent } from '@testing-library/react';

describe('Counter', () => {
  it('increments count on button click', () => {
    render(<Counter />);
    const button = screen.getByRole('button', { name: /increment/i });

    fireEvent.click(button);

    expect(screen.getByText('Count: 1')).toBeInTheDocument();
  });
});
```

### API Route Tests
```typescript
import { GET } from '@/app/api/users/route';

describe('GET /api/users', () => {
  it('returns list of users', async () => {
    const request = new Request('http://localhost:3000/api/users');
    const response = await GET(request);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.users).toHaveLength(3);
  });
});
```

### Hook Tests
```typescript
import { renderHook, act } from '@testing-library/react';
import { useCounter } from '@/hooks/useCounter';

describe('useCounter', () => {
  it('increments counter', () => {
    const { result } = renderHook(() => useCounter());

    act(() => {
      result.current.increment();
    });

    expect(result.current.count).toBe(1);
  });
});
```
