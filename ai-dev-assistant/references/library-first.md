# Library-First & CLI-First Development

Architecture principles enforced during Phase 2 design.

## Library-First Principle

Build functionality as reusable services BEFORE adding UI.

### The Pattern

```
1. MyService (src/MyService.php)
   ↓ Business logic, testable, reusable
2. MyForm (src/Form/MyForm.php)
   ↓ Uses MyService, handles UI only
3. my_module.routing.yml
   ↓ Exposes form at URL
```

### Why Library-First?

| Benefit | Explanation |
|---------|-------------|
| Testable | Services can be unit tested in isolation |
| Reusable | Multiple UIs can use same service |
| Maintainable | Business logic separate from presentation |
| CLI-ready | Drush commands can use same service |

### Enforcement

During `/design`, verify:

- [ ] Service designed BEFORE form/controller
- [ ] Service usable without any UI
- [ ] Business logic in service, NOT in form
- [ ] Form only handles: display, validation, routing to service

### Anti-Patterns

| Bad | Good |
|-----|------|
| Business logic in form `submitForm()` | Form calls service method |
| Controller does calculations | Controller calls service |
| Database queries in form | Service handles data access |

## CLI-First Principle

Every feature should be accessible via Drush command.

### The Pattern

```
1. MyService (business logic)
   ↓
2. MyCommand (src/Commands/MyCommand.php)
   ↓ Exposes service via Drush
3. MyForm (src/Form/MyForm.php)
   ↓ Also uses same service
```

### Why CLI-First?

| Benefit | Use Case |
|---------|----------|
| Automation | Cron jobs, scheduled tasks |
| Scripting | Batch operations |
| CI/CD | Automated deployments |
| Testing | Quick manual verification |
| Performance | No browser overhead |

### Enforcement

During `/design`, verify:

- [ ] Drush command planned alongside admin UI
- [ ] Command uses SAME service as UI
- [ ] No UI-only features (everything CLI-accessible)

### Drush Command Pattern

```php
namespace Drupal\my_module\Commands;

use Drush\Commands\DrushCommands;

class MyCommands extends DrushCommands {

  public function __construct(
    private readonly MyServiceInterface $myService,
  ) {
    parent::__construct();
  }

  /**
   * Description of what this does.
   *
   * @command my_module:do-thing
   * @aliases mdt
   */
  public function doThing(): void {
    $result = $this->myService->doThing();
    $this->io()->success("Done: $result");
  }
}
```

## Design Phase Checklist

Before completing `/design`:

### Library-First
- [ ] Services defined for all business logic
- [ ] Services have interfaces
- [ ] Forms/controllers only orchestrate, don't contain logic
- [ ] Services registered in services.yml with dependency injection

### CLI-First
- [ ] Drush command planned for each major feature
- [ ] Commands use same services as UI
- [ ] Command arguments/options documented
- [ ] No feature is UI-only

## Common Violations

| Violation | Detection | Fix |
|-----------|-----------|-----|
| Logic in form | `submitForm()` has calculations | Move to service |
| UI-only feature | No Drush command exists | Add command |
| Direct DB in form | `\Drupal::database()` in form | Create data service |
| No service layer | Form does everything | Extract service first |
