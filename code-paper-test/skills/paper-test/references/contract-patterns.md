# Code Contract Patterns

Comprehensive verification templates for all code relationship patterns.

## Contents

- [Pattern 1: Inheritance](#pattern-1-inheritance)
- [Pattern 2: Plugin System](#pattern-2-plugin-system)
- [Pattern 3: Service/Dependency Injection](#pattern-3-servicedependency-injection)
- [Pattern 4: Interface Implementation](#pattern-4-interface-implementation)
- [Pattern 5: Traits](#pattern-5-traits)
- [Pattern 6: Event/Hook Systems](#pattern-6-eventhook-systems)
- [Pattern 7: Middleware/Decorators](#pattern-7-middlewaredecorators)
- [Pattern 8: Service Collectors / Tagged Services](#pattern-8-service-collectors--tagged-services)

---

## Pattern 1: Inheritance

**When code extends a parent class:**

```php
class MyController extends ControllerBase {
  public function build() { }
}
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Parent exists | Read parent class file | Fatal error |
| Abstract methods | Read parent for abstract methods | Fatal error |
| Constructor | Does parent __construct need calling? | Uninitialized state |
| Protected properties | What properties inherited? | Wrong usage |
| Method overrides | Parent method signature | Type errors |

**Inheritance verification template:**
```
CLASS: [MyClass]
EXTENDS: [ParentClass]

PARENT CLASS REVIEW:
  Location: [path to parent class file]

  Abstract methods (MUST implement):
    - [ ] method1(Type $param): ReturnType
          My implementation: line [N]
    - [ ] method2(): void
          My implementation: line [N]

  Constructor:
    - [ ] Parent constructor exists
    - [ ] Requires parameters: [list]
    - [ ] My constructor calls parent::__construct()

  Protected/Public methods inherited:
    - method3() - what it does
    - method4() - what it does

  Protected properties inherited:
    - $this->property1 (type) - what it's for

VERIFICATION:
  - [ ] All abstract methods implemented
  - [ ] Parent constructor called (if required)
  - [ ] Inherited properties used correctly
  - [ ] Return types match parent expectations
```

---

## Pattern 2: Plugin System

**When code is a plugin:**

```php
#[Action(
  id: "my_action",
  label: new TranslatableMarkup("My Action"),
)]
class MyAction extends ConfigurableActionBase { }
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Annotation/Attribute | Read plugin manager for required fields | Plugin not discovered |
| Base class | Read base class for required methods | Runtime errors |
| Configuration | What config keys expected? Schema? | Form failures |
| Dependencies | What services available? How injected? | Null service errors |
| Plugin context | What context passed to plugin? | Missing data |

**Plugin verification template:**
```
PLUGIN: [PluginClass]
TYPE: [Action | Condition | Event | Field | Widget | etc.]
BASE CLASS: [BaseClassName]

ANNOTATION/ATTRIBUTE CHECK:
  Required fields from plugin manager:
    - [ ] id: [value]
    - [ ] label: [value]
    - [ ] [other required]: [value]

BASE CLASS REVIEW:
  Location: [file path]

  Required methods:
    - [ ] execute() / evaluate() / process()
    - [ ] defaultConfiguration()
    - [ ] buildConfigurationForm()

  Services provided by parent:
    - $this->service1 (how injected, when available)
    - $this->service2 (how injected, when available)

  Configuration access:
    - $this->configuration['key'] (what keys expected)
    - $this->getConfiguration() (returns what)

PLUGIN MANAGER CHECK:
  - How does manager create plugins?
  - What context passed to plugin?
  - What lifecycle hooks exist?
```

---

## Pattern 3: Service/Dependency Injection

**When code depends on injected services:**

```php
class MyService {
  public function __construct(
    private readonly LoggerInterface $logger,
    private readonly EntityTypeManagerInterface $entityTypeManager,
  ) {}
}
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Service exists | Check services.yml or container | Container error |
| Interface correct | Read interface for method signatures | Method not found |
| Method signatures | Read interface for parameters, returns | Type errors |
| Return types | What does method actually return? | Wrong usage |
| Side effects | Does method modify state? | Unexpected behavior |

**DI verification template:**
```
SERVICE: [MyService]
DEPENDENCIES:

1. LoggerInterface ($this->logger)
   Service ID: [logger.channel.my_module or similar]
   Interface location: [path]
   Methods used:
     - [ ] info() - signature: (string $message, array $context = [])
     - [ ] error() - signature: (string $message, array $context = [])

2. EntityTypeManagerInterface ($this->entityTypeManager)
   Service ID: [entity_type.manager]
   Interface location: [path]
   Methods used:
     - [ ] getStorage() - returns: EntityStorageInterface
     - [ ] getDefinition() - returns: EntityTypeInterface|null

INJECTION VERIFICATION:
  - [ ] All dependencies declared in services.yml (or auto-wired)
  - [ ] Interface type hints match actual service
  - [ ] All methods called exist in interface
  - [ ] Return types handled correctly
```

---

## Pattern 4: Interface Implementation

**When code implements an interface:**

```php
class MyHandler implements HandlerInterface {
  public function handle(Request $request): Response { }
}
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| All methods | Read interface for complete method list | Interface violation |
| Signatures | Exact parameter types and order | Type errors |
| Return types | Interface-declared return type | Type errors |
| Semantics | Interface documentation for behavior | Wrong behavior |

**Interface verification template:**
```
CLASS: [MyClass]
IMPLEMENTS: [Interface1], [Interface2]

INTERFACE: Interface1
  Location: [path]

  Required methods:
    - [ ] method1(Type $param): ReturnType
          My implementation: line [N]
          Signature matches: [YES/NO]

    - [ ] method2(): void
          My implementation: line [N]
          Signature matches: [YES/NO]

  Semantic requirements (from docs):
    - method1 must: [expected behavior]
    - method2 must: [expected behavior]
```

---

## Pattern 5: Traits

**When code uses traits:**

```php
class MyClass {
  use LoggerTrait;
  use EntityTrait;
}
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Trait requirements | Does trait expect properties/methods? | Undefined errors |
| Conflicts | Multiple traits with same method? | Ambiguity errors |
| Initialization | Does trait need setup? | Null properties |
| Abstract methods | Trait may declare abstract methods | Fatal errors |

**Trait verification template:**
```
CLASS: [MyClass]
USES TRAITS: [Trait1], [Trait2]

TRAIT: Trait1
  Location: [path]

  Properties provided:
    - $this->property1 (type)

  Methods provided:
    - method1() - does what

  Requirements from host class:
    - [ ] Expects $this->requiredProperty
    - [ ] Expects method requiredMethod()

  Abstract methods requiring implementation:
    - [ ] abstractMethod()

CONFLICT CHECK:
  - Trait1::method() vs Trait2::method()? [CONFLICT/NO CONFLICT]
  - Resolution: [how resolved]
```

---

## Pattern 6: Event/Hook Systems

**When code handles events or hooks:**

```php
// Drupal hook
function mymodule_entity_presave(EntityInterface $entity) { }

// Symfony event subscriber
public function onKernelRequest(RequestEvent $event) { }
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Signature | Read dispatcher for expected parameters | Missing data |
| Return value | What does dispatcher expect returned? | Broken chain |
| Order | When does this fire relative to others? | Race conditions |
| Event object | What methods/data on event object? | Wrong access |

**Event verification template:**
```
HOOK/EVENT: [hook_name or EventClass]

DISPATCHER CHECK:
  Where dispatched: [file:line]

  Expected signature:
    - Parameter 1: [Type] $name - what it contains
    - Parameter 2: [Type] $name - what it contains

  Return expectation:
    - Return type: [void | mixed | specific]
    - Return affects: [nothing | stops propagation | modifies data]

EVENT OBJECT (if applicable):
  Methods available:
    - [ ] getEntity() - returns EntityInterface
    - [ ] stopPropagation() - prevents further handlers
    - [ ] getData() - returns [type]

MY IMPLEMENTATION:
  - [ ] Signature matches expected
  - [ ] Return type correct
  - [ ] Event object methods exist
```

---

## Pattern 7: Middleware/Decorators

**When code wraps or decorates:**

```php
class MyMiddleware implements MiddlewareInterface {
  public function process(Request $request, Handler $handler): Response {
    // before
    $response = $handler->handle($request);
    // after
    return $response;
  }
}
```

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Chain call | Must call next handler? | Broken chain |
| Request mutation | Can/should modify request? | Unexpected state |
| Response handling | Must return response? Modify it? | Lost response |
| Order | Where in stack? Before/after what? | Wrong timing |

**Middleware verification template:**
```
MIDDLEWARE: [MiddlewareClass]
IMPLEMENTS: [MiddlewareInterface]

INTERFACE CHECK:
  Location: [path]
  Required signature: process(Request $request, Handler $handler): Response

CHAIN VERIFICATION:
  - [ ] Calls $handler->handle($request)
  - [ ] Returns Response object
  - [ ] Proper exception handling

STACK POSITION:
  - Where registered: [middleware config file]
  - Priority/order: [value]
  - Runs before: [other middleware]
  - Runs after: [other middleware]

REQUEST/RESPONSE HANDLING:
  - Modifies request: [yes/no - how]
  - Modifies response: [yes/no - how]
  - Can short-circuit: [yes/no]
```

---

## Pattern 8: Service Collectors / Tagged Services

**When services are dynamically collected via tags:**

This pattern is used when a "manager" service aggregates multiple "worker" services that register themselves via tags. The manager doesn't know ahead of time which services will be collected.

```yaml
# services.yml - Service registers itself with a tag
services:
  my_module.my_breadcrumb_builder:
    class: Drupal\my_module\MyBreadcrumbBuilder
    tags:
      - { name: breadcrumb_builder, priority: 100 }
```

```php
// The collected service must implement the expected interface
class MyBreadcrumbBuilder implements BreadcrumbBuilderInterface {
  public function applies(RouteMatchInterface $route_match): bool { }
  public function build(RouteMatchInterface $route_match): Breadcrumb { }
}
```

**Common collector patterns:**

| Pattern | Tag | Collector | Interface Required |
|---------|-----|-----------|-------------------|
| Breadcrumbs | `breadcrumb_builder` | BreadcrumbManager | BreadcrumbBuilderInterface |
| Access checks | `access_check` | AccessManager | AccessInterface |
| Route subscribers | `event_subscriber` | EventDispatcher | EventSubscriberInterface |
| Param converters | `paramconverter` | ParamConverterManager | ParamConverterInterface |
| Normalizers | `normalizer` | Serializer | NormalizerInterface |
| Context providers | `context_provider` | ContextRepository | ContextProviderInterface |
| Validation constraints | `validation.constraint_validator` | ConstraintValidatorFactory | ConstraintValidatorInterface |

**What to verify:**

| Check | How to Verify | Risk if Wrong |
|-------|---------------|---------------|
| Tag name | Read collector for expected tag name | Service not discovered |
| Tag attributes | priority, id, method - what's required? | Wrong order, missing calls |
| Interface | What interface does collector expect? | Method not found errors |
| Method signatures | Read interface for exact signatures | Type errors |
| Return values | What does collector do with returns? | Logic failures |
| Execution order | Does priority matter for your use case? | Race conditions |

**Service collector verification template:**
```
TAGGED SERVICE: [MyService]
TAG: [tag_name]
COLLECTOR: [CollectorService]

TAG CONFIGURATION:
  Location: services.yml or services annotation
  Tag name: [exact tag name]
  Tag attributes:
    - priority: [value] (higher = earlier?)
    - id: [if required]
    - method: [if collector calls specific method]

COLLECTOR CHECK:
  Location: [collector class file]

  How collector discovers services:
    - Compiler pass? ServiceCollectorInterface? Manual?

  How collector invokes services:
    - Calls method: [method name]
    - Passes parameters: [what params]
    - Expects return: [what return type]

  Execution order:
    - Priority direction: [higher first / lower first]
    - Can stop chain: [yes/no]

INTERFACE REQUIRED:
  Interface: [InterfaceName]
  Location: [path]

  Required methods:
    - [ ] method1(params): ReturnType
    - [ ] method2(params): ReturnType

MY IMPLEMENTATION CHECK:
  - [ ] Tag name exactly matches collector expectation
  - [ ] All required tag attributes present
  - [ ] Implements correct interface
  - [ ] All interface methods implemented
  - [ ] Method signatures match exactly
  - [ ] Return types correct for collector logic
  - [ ] Priority appropriate for use case
```

**Framework-specific examples:**

**Drupal - Breadcrumb Builder:**
```yaml
services:
  my_module.breadcrumb:
    class: Drupal\my_module\Breadcrumb\MyBreadcrumbBuilder
    tags:
      - { name: breadcrumb_builder, priority: 1000 }
```
```php
class MyBreadcrumbBuilder implements BreadcrumbBuilderInterface {
  // MUST implement applies() - collector calls this first
  public function applies(RouteMatchInterface $route_match): bool {
    return $route_match->getRouteName() === 'my_module.my_route';
  }

  // MUST implement build() - only called if applies() returns TRUE
  public function build(RouteMatchInterface $route_match): Breadcrumb {
    $breadcrumb = new Breadcrumb();
    // ... build breadcrumb
    return $breadcrumb;  // MUST return Breadcrumb object
  }
}
```

**Symfony - Event Subscriber:**
```yaml
services:
  my_bundle.event_subscriber:
    class: MyBundle\EventSubscriber\MySubscriber
    tags:
      - { name: kernel.event_subscriber }
```
```php
class MySubscriber implements EventSubscriberInterface {
  // MUST implement getSubscribedEvents() - tells dispatcher what to call
  public static function getSubscribedEvents(): array {
    return [
      KernelEvents::REQUEST => ['onKernelRequest', 10],
      KernelEvents::RESPONSE => 'onKernelResponse',
    ];
  }

  public function onKernelRequest(RequestEvent $event): void {
    // Handler implementation
  }
}
```

---

## Quick Contract Detection

Use this to quickly identify which pattern applies:

| Code Pattern | Contract Type |
|--------------|---------------|
| `extends ParentClass` | Pattern 1: Inheritance |
| `#[Plugin(...)]` or `@Plugin(...)` | Pattern 2: Plugin System |
| `__construct(ServiceInterface $service)` | Pattern 3: Dependency Injection |
| `implements InterfaceX` | Pattern 4: Interface Implementation |
| `use TraitName;` | Pattern 5: Traits |
| `function hook_*()` or `EventSubscriberInterface` | Pattern 6: Event/Hook Systems |
| `MiddlewareInterface` or `process()` method | Pattern 7: Middleware |
| `tags: [{ name: ... }]` in services.yml | Pattern 8: Service Collectors |

---

## Common Contract Violations

**Missing abstract method implementation:**
```php
// Parent has abstract method
abstract class Base {
  abstract public function process(): void;
}

// Child MUST implement it
class Child extends Base {
  // VIOLATION: Missing process() method
}
```

**Wrong interface signature:**
```php
// Interface defines exact signature
interface Handler {
  public function handle(Request $request): Response;
}

// VIOLATION: Wrong parameter type
class MyHandler implements Handler {
  public function handle(array $request): Response { }
  //                      ^^^^^ should be Request
}
```

**Plugin missing required annotation fields:**
```php
// VIOLATION: Missing required 'id' field
#[Action(
  label: new TranslatableMarkup("My Action")
)]
class MyAction extends ActionBase { }
```

**Tagged service not implementing required interface:**
```yaml
services:
  my.breadcrumb:
    class: My\Class
    tags:
      - { name: breadcrumb_builder }
```
```php
// VIOLATION: Must implement BreadcrumbBuilderInterface
class My\Class {
  // Missing applies() and build() methods
}
```
