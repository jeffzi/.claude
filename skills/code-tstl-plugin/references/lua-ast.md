# Lua AST Quick Reference

- [Factory Functions](#factory-functions)
- [Type Guards](#type-guards)
- [Reserved Word Keys](#reserved-word-keys)

## Factory Functions

```typescript
// Literals and identifiers
tstl.createIdentifier("name")
tstl.createStringLiteral("value")
tstl.createNumericLiteral(42)
tstl.createBooleanLiteral(true)
tstl.createNilLiteral()

// Expressions
tstl.createCallExpression(callee, [arg1, arg2])
tstl.createTableIndexExpression(table, key)   // table[key] or table.key
tstl.createTableExpression([field1, field2])   // { k = v, ... }
tstl.createTableFieldExpression(value, key)    // key = value
tstl.createBinaryExpression(left, op, right)
tstl.createUnaryExpression(operand, op)

// Statements
tstl.createExpressionStatement(expr)
tstl.createReturnStatement([expr1, expr2])
tstl.createVariableDeclarationStatement(ident, initializer)
tstl.createAssignmentStatement(ident, value)
```

## Type Guards

Every factory has a matching `tstl.is*` guard: `tstl.isStringLiteral()`, `tstl.isCallExpression()`,
`tstl.isIdentifier()`, `tstl.isReturnStatement()`, `tstl.isIfStatement()`, etc.

## Reserved Word Keys

Lua keywords (`end`, `repeat`, `until`, etc.) require bracket notation in `TableIndexExpression`:

```typescript
// "end" is a Lua keyword — use string literal key
const key = tstl.createStringLiteral("end");
const access = tstl.createTableIndexExpression(obj, key);
// Emits: obj["end"]
```
