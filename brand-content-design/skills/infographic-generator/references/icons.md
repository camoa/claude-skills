# Icons Reference

## Icon Syntax

Use icons in icon-based templates with this syntax:
```json
{ "label": "icon:rocket", "desc": "Fast deployment" }
```

## Icon Templates

Only these templates support icons:
```
list-grid-horizontal-icon-arrow
list-row-horizontal-icon-arrow
list-row-horizontal-icon-line
list-column-vertical-icon-arrow
sequence-color-snake-steps-horizontal-icon-line
sequence-horizontal-zigzag-horizontal-icon-line
relation-circle-icon-badge
```

## Available Icons

The library uses Lucide icons. Common icons:

### Business
| Icon | Name |
|------|------|
| briefcase | `icon:briefcase` |
| building | `icon:building` |
| dollar-sign | `icon:dollar-sign` |
| trending-up | `icon:trending-up` |
| chart-bar | `icon:chart-bar` |
| pie-chart | `icon:pie-chart` |

### Technology
| Icon | Name |
|------|------|
| rocket | `icon:rocket` |
| cloud | `icon:cloud` |
| server | `icon:server` |
| database | `icon:database` |
| code | `icon:code` |
| terminal | `icon:terminal` |
| cpu | `icon:cpu` |
| wifi | `icon:wifi` |
| globe | `icon:globe` |

### Communication
| Icon | Name |
|------|------|
| mail | `icon:mail` |
| message-circle | `icon:message-circle` |
| phone | `icon:phone` |
| video | `icon:video` |
| users | `icon:users` |
| user | `icon:user` |

### Actions
| Icon | Name |
|------|------|
| check | `icon:check` |
| check-circle | `icon:check-circle` |
| x | `icon:x` |
| plus | `icon:plus` |
| minus | `icon:minus` |
| edit | `icon:edit` |
| trash | `icon:trash` |
| download | `icon:download` |
| upload | `icon:upload` |

### Objects
| Icon | Name |
|------|------|
| file | `icon:file` |
| folder | `icon:folder` |
| image | `icon:image` |
| camera | `icon:camera` |
| calendar | `icon:calendar` |
| clock | `icon:clock` |
| lock | `icon:lock` |
| key | `icon:key` |
| shield | `icon:shield` |

### Arrows
| Icon | Name |
|------|------|
| arrow-right | `icon:arrow-right` |
| arrow-left | `icon:arrow-left` |
| arrow-up | `icon:arrow-up` |
| arrow-down | `icon:arrow-down` |
| chevron-right | `icon:chevron-right` |
| external-link | `icon:external-link` |

### Status
| Icon | Name |
|------|------|
| alert-circle | `icon:alert-circle` |
| alert-triangle | `icon:alert-triangle` |
| info | `icon:info` |
| help-circle | `icon:help-circle` |
| star | `icon:star` |
| heart | `icon:heart` |
| thumbs-up | `icon:thumbs-up` |

### Nature
| Icon | Name |
|------|------|
| sun | `icon:sun` |
| moon | `icon:moon` |
| zap | `icon:zap` |
| activity | `icon:activity` |
| target | `icon:target` |
| compass | `icon:compass` |

## Example Data

```json
{
  "title": "Our Services",
  "items": [
    { "label": "icon:cloud", "desc": "Cloud Infrastructure" },
    { "label": "icon:shield", "desc": "Security Services" },
    { "label": "icon:chart-bar", "desc": "Analytics" },
    { "label": "icon:code", "desc": "Development" }
  ]
}
```

## Text Overlap Warning

Icon templates have less space for text. Keep:
- Labels: 1-2 words only
- Descriptions: 2-4 words max

If text overlaps, use a text-only template like `list-grid-simple` or `list-column-done-list`.

## Full Icon List

For the complete list of 1000+ Lucide icons, see:
https://lucide.dev/icons/
