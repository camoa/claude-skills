# TDD Workflow Reference

Test-Driven Development guidance for Drupal projects.

> **Online Dev-Guides:** For comprehensive TDD patterns, test naming, spec-driven development, and testing anti-patterns, see https://camoa.github.io/dev-guides/drupal/tdd/ (26 guides covering RED-GREEN-REFACTOR, test types, coverage strategy, and testing every Drupal component type).

## RED-GREEN-REFACTOR Cycle

### RED Phase
Write a failing test BEFORE implementation.

**What to do:**
1. Identify the behavior to implement
2. Write a test that describes the expected behavior
3. Run test - it MUST fail
4. Failure confirms you're testing new functionality

**Test naming pattern:**
```php
public function testMethodName_condition_expectedResult(): void
```

**Example:**
```php
public function testValidate_withEmptyTitle_throwsException(): void {
    $this->expectException(ValidationException::class);
    $validator = new ContentValidator();
    $validator->validate(['title' => '']);
}
```

### GREEN Phase
Write minimal code to make the test pass.

**Rules:**
- Only write enough code to pass the test
- Don't optimize or clean up yet
- It's OK to hardcode values temporarily
- Focus on making the test green, nothing else

**Example:**
```php
public function validate(array $data): void {
    if (empty($data['title'])) {
        throw new ValidationException('Title required');
    }
}
```

### REFACTOR Phase
Clean up while keeping tests green.

**What to refactor:**
- Remove duplication (DRY)
- Improve variable/method names
- Extract methods for clarity
- Add type hints
- Simplify conditionals

**Rules:**
- Run tests after each small change
- If tests fail, undo and try smaller step
- Don't add new functionality here

## When TDD Makes Sense

**Good candidates:**
- Services with complex business logic
- Plugins with clear contracts
- API controllers/endpoints
- Form validation logic
- Entity hooks and event subscribers
- Anything with clear inputs/outputs

**Skip strict TDD for:**
- Configuration/YAML files
- Exploratory/prototype code
- Simple CRUD operations
- Theme/frontend templates
- One-off migrations

## Test Type Selection for TDD

| Scenario | Test Type | Speed |
|----------|-----------|-------|
| Pure logic, no dependencies | Unit | ~1ms |
| Needs Drupal services | Kernel | ~100ms |
| Needs full bootstrap, forms | Functional | ~1s |
| Needs JavaScript | FunctionalJavascript | ~5s |

**Rule:** Start with Kernel tests for Drupal TDD.

## TDD Patterns in Drupal

### Testing Services

```php
// Kernel test - has container access
class MyServiceTest extends KernelTestBase {
    protected static $modules = ['my_module'];

    public function testProcess_withValidInput_returnsExpected(): void {
        $service = $this->container->get('my_module.my_service');
        $result = $service->process(['key' => 'value']);
        $this->assertEquals('expected', $result);
    }
}
```

### Testing Plugins

```php
class MyPluginTest extends KernelTestBase {
    public function testBuild_withConfiguration_rendersCorrectly(): void {
        $plugin = $this->container
            ->get('plugin.manager.block')
            ->createInstance('my_plugin', ['config' => 'value']);

        $build = $plugin->build();
        $this->assertArrayHasKey('#markup', $build);
    }
}
```

### Testing Forms

```php
class MyFormTest extends KernelTestBase {
    use FormTestTrait;

    public function testValidation_withInvalidData_hasErrors(): void {
        $form_state = new FormState();
        $form_state->setValues(['field' => 'invalid']);

        $form = MyForm::create($this->container);
        $form->validateForm([], $form_state);

        $this->assertTrue($form_state->hasAnyErrors());
    }
}
```

## Cycle Frequency

**Target:** 20-40 cycles per hour during active TDD.

**Signs you're doing it right:**
- Each cycle takes 1-3 minutes
- Tests are small and focused
- Failures are informative
- Green gives confidence

**Signs of problems:**
- Cycles take >10 minutes
- Multiple tests fail at once
- Unclear why test failed
- Lots of debugging in GREEN phase

## Resources

- [Oliver Davies: TDD in Drupal](https://www.oliverdavies.uk/blog/writing-new-drupal-8-module-using-test-driven-development-tdd)
- [Drupal Commerce: Unit, Kernel, Functional Tests](https://drupalcommerce.org/blog/45322/commerce-2x-unit-kernel-and-functional-tests-oh-my)
