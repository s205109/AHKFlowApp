---
alwaysApply: true
description: >
  Enforces naming conventions for controllers, DTOs, commands, queries, and handlers.
---

# Naming Rules

- Controllers: plural (`HotstringsController`, `ProfilesController`)
- DTOs: `{Entity}Dto`, `Create{Entity}Dto`, `Update{Entity}Dto` (records)
- Commands: `Create{Entity}Command`, `Update{Entity}Command`, `Delete{Entity}Command`
- Queries: `Get{Entity}Query`, `List{Entities}Query`
- Handlers: `{Command/Query}Handler`
- Validators: `{Command/Query}Validator`
- Async methods: `*Async` suffix
- EF configurations: `{Entity}Configuration` implementing `IEntityTypeConfiguration<T>`
