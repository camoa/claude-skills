# Canvas (JSX) Generation Patterns

## Contents
- JavaScriptComponent structure
- Props definition
- JSX patterns
- Using CVA for variants
- Tailwind CSS patterns

## JavaScriptComponent Config Entity

Canvas components are stored as config entities, not filesystem files.

### Basic Structure
```yaml
# config/install/js_component.component_name.yml
langcode: en
status: true
dependencies:
  enforced:
    module:
      - your_module
machineName: component_name
name: Component Name
props:
  heading:
    type: string
    title: Heading
    examples:
      - 'Welcome'
required:
  - heading
slots: {}
js:
  original: |
    export default function ComponentName({ heading = "Welcome" }) {
      return (
        <div className="p-4">
          <h1 className="text-2xl font-bold">{heading}</h1>
        </div>
      );
    }
  compiled: ''
css:
  original: ''
  compiled: ''
dataDependencies: {}
```

## Props Definition

### Basic Types
```yaml
props:
  # String
  heading:
    type: string
    title: Heading
    examples: ['Hello World']

  # Boolean
  isVisible:
    type: boolean
    title: Visible
    examples: [true]

  # Number
  count:
    type: number
    title: Count
    examples: [5]

  # Enum (list)
  variant:
    type: string
    title: Variant
    enum: [primary, secondary]
    examples: ['primary']
```

### Image Props
```yaml
props:
  photo:
    type: object
    title: Photo
    properties:
      src:
        type: string
        format: uri
      alt:
        type: string
      width:
        type: number
      height:
        type: number
```

### Required Props
```yaml
props:
  title:
    type: string
    title: Title
required:
  - title
```

## JSX Component Patterns

### Basic Component
```javascript
export default function HeroBanner({
  heading = "Welcome",
  subheading,
  buttonText = "Learn More",
  buttonUrl
}) {
  return (
    <div className="relative py-16 px-4 bg-gray-100">
      <h1 className="text-4xl font-bold mb-4">{heading}</h1>
      {subheading && (
        <p className="text-xl text-gray-600 mb-8">{subheading}</p>
      )}
      {buttonUrl && (
        <a
          href={buttonUrl}
          className="inline-block px-6 py-3 bg-blue-600 text-white rounded-lg"
        >
          {buttonText}
        </a>
      )}
    </div>
  );
}
```

### With Image
```javascript
import Image from 'next-image-standalone';

export default function Card({
  title,
  photo,
  children
}) {
  return (
    <div className="rounded-lg shadow-lg overflow-hidden">
      {photo && (
        <Image
          src={photo.src}
          alt={photo.alt}
          width={photo.width}
          height={photo.height}
          className="w-full h-48 object-cover"
        />
      )}
      <div className="p-4">
        <h2 className="text-xl font-semibold">{title}</h2>
        {children}
      </div>
    </div>
  );
}
```

### With Slots (Children)
```javascript
export default function Container({
  title,
  children  // This is a slot
}) {
  return (
    <section className="py-8">
      {title && <h2 className="text-2xl font-bold mb-4">{title}</h2>}
      <div className="content">
        {children}
      </div>
    </section>
  );
}
```

## Using CVA for Variants

Class Variance Authority (CVA) is required for style variants.

### Basic CVA Usage
```javascript
import { cva } from 'class-variance-authority';

const buttonStyles = cva(
  // Base styles
  'inline-flex items-center justify-center rounded-lg font-medium transition-colors',
  {
    variants: {
      intent: {
        primary: 'bg-blue-600 text-white hover:bg-blue-700',
        secondary: 'bg-gray-200 text-gray-800 hover:bg-gray-300',
        outline: 'border-2 border-blue-600 text-blue-600 hover:bg-blue-50',
      },
      size: {
        sm: 'px-3 py-1.5 text-sm',
        md: 'px-4 py-2 text-base',
        lg: 'px-6 py-3 text-lg',
      },
    },
    defaultVariants: {
      intent: 'primary',
      size: 'md',
    },
  }
);

export default function Button({
  label,
  intent = 'primary',
  size = 'md',
  url
}) {
  return (
    <a href={url} className={buttonStyles({ intent, size })}>
      {label}
    </a>
  );
}
```

### Props Metadata for CVA
```yaml
props:
  intent:
    type: string
    title: Intent
    enum: [primary, secondary, outline]
    examples: ['primary']
  size:
    type: string
    title: Size
    enum: [sm, md, lg]
    examples: ['md']
```

## Tailwind CSS Patterns

### Common Utilities
```javascript
// Layout
className="flex flex-col items-center justify-center"
className="grid grid-cols-2 gap-4"

// Spacing
className="p-4 m-2"
className="px-6 py-3"
className="space-y-4"

// Typography
className="text-2xl font-bold text-gray-900"
className="text-sm text-gray-500"

// Colors
className="bg-blue-600 text-white"
className="bg-gradient-to-r from-blue-500 to-purple-600"

// Effects
className="shadow-lg rounded-xl"
className="hover:scale-105 transition-transform"
```

### Responsive Design
```javascript
className="text-lg md:text-xl lg:text-2xl"
className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
className="p-4 md:p-6 lg:p-8"
```

## Data Fetching

Only add data fetching if the component needs dynamic content.

### Using SWR with JSON:API
```javascript
import useSWR from 'swr';
import { JsonApiClient } from '@drupal-api-client/json-api-client';
import { DrupalJsonApiParams } from 'drupal-jsonapi-params';

const client = new JsonApiClient();

export default function ArticleList() {
  const { data, error, isLoading } = useSWR(
    [
      'node--article',
      {
        queryString: new DrupalJsonApiParams()
          .addFields('node--article', ['title', 'field_image'])
          .addInclude(['field_image'])
          .getQueryString(),
      },
    ],
    ([type, options]) => client.getCollection(type, options)
  );

  if (isLoading) return <div>Loading...</div>;
  if (error) return <div>Error loading articles</div>;

  return (
    <ul>
      {data.map((article) => (
        <li key={article.id}>{article.title}</li>
      ))}
    </ul>
  );
}
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `@apply` in CSS | Apply Tailwind classes directly in className |
| Missing CVA for variants | Always use CVA for style variants |
| Prop name mismatch | Ensure props metadata ID matches function argument |
| Using `<img>` | Use `<Image>` from next-image-standalone |
| Hardcoding colors | Use Tailwind color classes |
