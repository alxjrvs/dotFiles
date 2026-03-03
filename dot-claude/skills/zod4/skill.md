# Zod 4 Reference Skill

Use when writing or modifying Zod schemas, migrating from Zod 3, or generating JSON schemas. Applies to any project using `zod@^4.x`.

## Zod 3 to Zod 4 Migration

### Breaking Changes

| v3 | v4 | Notes |
|----|-----|-------|
| `A.merge(B)` | `A.extend({ ...B.shape })` | `.merge()` removed |
| `z.record(valueSchema)` | `z.record(z.string(), valueSchema)` | Key schema now required |
| `error.errors` | `error.issues` | `.errors` alias removed from `ZodError` |
| `z.enum().options` returns `readonly [string, ...string[]]` | Returns `readonly string[]` | Tuple type dropped |
| `message`, `invalid_type_error`, `required_error` | `error: (issue) => string` | Unified error param |
| `.describe("text")` | `.meta({ description: "text" })` | `.describe()` still works but deprecated |

### JSON Schema Generation (replaces zod-to-json-schema)

```typescript
import { z } from 'zod'

const schema = z.object({ name: z.string(), age: z.number() })

// Basic usage
const jsonSchema = z.toJSONSchema(schema)

// With options
const jsonSchema = z.toJSONSchema(schema, {
  target: 'draft-07',        // 'draft-04' | 'draft-07' | 'draft-2020-12' (default) | 'openapi-3.0'
  io: 'output',              // 'input' | 'output' (default)
  unrepresentable: 'any',    // 'throw' (default) | 'any' (emit {} for unrepresentable types)
  cycles: 'ref',             // 'ref' (default) | 'throw'
  reused: 'inline',          // 'inline' (default) | 'ref' (extract to $defs)
})
```

### New Schema Types

```typescript
// Template literals
z.templateLiteral([z.literal("user_"), z.number()])  // "user_42"

// File validation
z.file().min(1024).max(5_000_000).mime(["image/png", "image/jpeg"])

// Boolean-like strings
z.stringbool()  // "true"/"yes"/"on"/"1" -> true, etc.

// Top-level format validators
z.email()   // instead of z.string().email()
z.uuid()    // instead of z.string().uuid()
z.url()     // instead of z.string().url()
z.ipv4()
z.cuid2()
```

### Recursive Types (no more z.lazy workaround)

```typescript
// v3 - required z.lazy() + explicit type annotation
const Category: z.ZodType<{ name: string; sub: Category[] }> = z.lazy(() =>
  z.object({ name: z.string(), sub: z.array(Category) })
)

// v4 - native getter support (also works with z.interface)
const Category = z.object({
  name: z.string(),
  get sub() { return z.array(Category) },
})
```

### Error Handling

```typescript
// v4 ZodError
try {
  schema.parse(data)
} catch (err) {
  if (err instanceof z.ZodError) {
    console.log(err.issues)          // array of ZodIssue
    console.log(z.prettifyError(err)) // formatted string
  }
}

// safeParse unchanged
const result = schema.safeParse(data)
if (!result.success) {
  result.error.issues  // ZodIssue[]
}
```

### Performance

- String parsing: ~15x faster
- Object parsing: ~7x faster
- Bundle: 57% smaller
- TS instantiations: ~100x fewer
