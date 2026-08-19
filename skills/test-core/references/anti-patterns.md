# Testing Anti-Patterns

**Load this reference when:** writing or changing tests, adding mocks, reviewing tests that use
mocks, writing a test that varies inputs over one code path, or tempted to add test-only methods to
production code.

## Table of Contents

- [Overview](#overview)
- [The Iron Laws](#the-iron-laws)
- [Anti-Pattern 1: Testing Mock Behavior](#anti-pattern-1-testing-mock-behavior)
- [Anti-Pattern 2: Test-Only Methods in Production](#anti-pattern-2-test-only-methods-in-production)
- [Anti-Pattern 3: Mocking Without Understanding](#anti-pattern-3-mocking-without-understanding)
- [Anti-Pattern 4: Incomplete Mocks](#anti-pattern-4-incomplete-mocks)
- [Anti-Pattern 5: Stacked Assertions Over Varying Inputs](#anti-pattern-5-stacked-assertions-over-varying-inputs)
- [When Mocks Become Too Complex](#when-mocks-become-too-complex)
- [Red Flags](#red-flags)

## Overview

Tests must verify real behavior, not mock behavior. Mocks are a means to isolate, not the thing
being tested. Each test proves one claim at a time — stacking assertions in a loop collapses the
independence that makes tests diagnosable.

**Core principle:** Test what the code does, not what the mocks do.

**Following strict TDD prevents most of these anti-patterns.**

## The Iron Laws

```text
1. NEVER test mock behavior
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
4. NEVER stack assertions over varying inputs inside one test
```

## Anti-Pattern 1: Testing Mock Behavior

**The violation:**

```typescript
// BAD: Testing that the mock exists
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
});
```

**Why this is wrong:**

- You're verifying the mock works, not that the component works
- Test passes when mock is present, fails when it's not
- Tells you nothing about real behavior

**Ask yourself:** "Am I testing real component behavior or just mock existence?"

**The fix:**

```typescript
// GOOD: Test real component or don't mock it
test('renders sidebar', () => {
  render(<Page />);  // Don't mock sidebar
  expect(screen.getByRole('navigation')).toBeInTheDocument();
});

// OR if sidebar must be mocked for isolation:
// Don't assert on the mock — test Page's behavior with sidebar present
```

### Gate Function: Mock Assertions

```text
BEFORE asserting on any mock element:
  Ask: "Am I testing real component behavior or just mock existence?"

  IF testing mock existence:
    STOP — delete the assertion or unmock the component

  Test real behavior instead
```

## Anti-Pattern 2: Test-Only Methods in Production

**The violation:**

```typescript
// BAD: destroy() only used in tests
class Session {
  async destroy() {  // Looks like production API!
    await this._workspaceManager?.destroyWorkspace(this.id);
    // ... cleanup
  }
}

// In tests
afterEach(() => session.destroy());
```

**Why this is wrong:**

- Production class polluted with test-only code
- Dangerous if accidentally called in production
- Violates YAGNI and separation of concerns
- Confuses object lifecycle with entity lifecycle

**The fix:**

```typescript
// GOOD: Test utilities handle test cleanup
// Session has no destroy() — it's stateless in production

// In test-utils/
export async function cleanupSession(session: Session) {
  const workspace = session.getWorkspaceInfo();
  if (workspace) {
    await workspaceManager.destroyWorkspace(workspace.id);
  }
}

// In tests
afterEach(() => cleanupSession(session));
```

### Gate Function: Test-Only Methods

```text
BEFORE adding any method to a production class:
  Ask: "Is this only used by tests?"

  IF yes:
    STOP — don't add it
    Put it in test utilities instead

  Ask: "Does this class own this resource's lifecycle?"

  IF no:
    STOP — wrong class for this method
```

## Anti-Pattern 3: Mocking Without Understanding

**The violation:**

```typescript
// BAD: Mock breaks test logic
test('detects duplicate server', () => {
  // Mock prevents config write that test depends on!
  vi.mock('ToolCatalog', () => ({
    discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)
  }));

  await addServer(config);
  await addServer(config);  // Should throw — but won't!
});
```

**Why this is wrong:**

- Mocked method had a side effect the test depended on (writing config)
- Over-mocking to "be safe" breaks actual behavior
- Test passes for the wrong reason, or fails mysteriously

**The fix:**

```typescript
// GOOD: Mock at the correct level
test('detects duplicate server', () => {
  // Mock the slow part, preserve behavior the test needs
  vi.mock('MCPServerManager'); // Just mock slow server startup

  await addServer(config);  // Config written
  await addServer(config);  // Duplicate detected
});
```

### Gate Function: Mocking Decisions

```text
BEFORE mocking any method:
  STOP — don't mock yet

  1. Ask: "What side effects does the real method have?"
  2. Ask: "Does this test depend on any of those side effects?"
  3. Ask: "Do I fully understand what this test needs?"

  IF depends on side effects:
    Mock at lower level (the actual slow/external operation)
    OR use test doubles that preserve necessary behavior
    NOT the high-level method the test depends on

  IF unsure what test depends on:
    Run test with real implementation FIRST
    Observe what actually needs to happen
    THEN add minimal mocking at the right level

  Red flags:
    - "I'll mock this to be safe"
    - "This might be slow, better mock it"
    - Mocking without understanding the dependency chain
```

## Anti-Pattern 4: Incomplete Mocks

**The violation:**

```typescript
// BAD: Partial mock — only fields you think you need
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' }
  // Missing: metadata that downstream code uses
};

// Later: breaks when code accesses response.metadata.requestId
```

**Why this is wrong:**

- **Partial mocks hide structural assumptions** — you only mocked fields you know about
- **Downstream code may depend on fields you didn't include** — silent failures
- **Tests pass but integration fails** — mock incomplete, real API complete
- **False confidence** — test proves nothing about real behavior

**The Iron Rule:** Mock the COMPLETE data structure as it exists in reality, not just fields your
immediate test uses.

**The fix:**

```typescript
// GOOD: Mirror real API completeness
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  metadata: { requestId: 'req-789', timestamp: 1234567890 }
  // All fields the real API returns
};
```

### Gate Function: Mock Completeness

```text
BEFORE creating a mock response:
  Check: "What fields does the real API response contain?"

  Actions:
    1. Examine actual API response from docs/examples
    2. Include ALL fields the system might consume downstream
    3. Verify the mock matches the real response schema completely

  Critical:
    If you're creating a mock, you must understand the ENTIRE structure.
    Partial mocks fail silently when code depends on omitted fields.

  If uncertain: include all documented fields.
```

## Anti-Pattern 5: Stacked Assertions Over Varying Inputs

**The violation:**

```python
# BAD: one test body, many inputs, hand-rolled loop
def test_validate_email():
    cases = [
        ("a@b.co",       True),
        ("no-at-sign",   False),
        ("trailing@",    False),
        ("multi@a@b.co", False),
    ]
    for email, expected in cases:
        assert validate_email(email) == expected
```

**Why this is wrong:**

- **The loop stops at the first failure.** You never learn which _other_ cases fail in the same run
  — one bug hides the rest.
- **Failure messages lose their input.** The reporter prints the generic test name, not the
  offending case, forcing you to instrument the loop with `pytest.fail` or a comment to figure out
  which input broke.
- **Test counts lie.** CI reports "1 test, 1 failure" when you actually had four cases — coverage
  dashboards and flaky-test detectors cannot see the cases individually.
- **Adding a case is invisible in history.** Diff readers just see a new tuple in a list instead of
  a new named test.

**The fix:** Use your language's parametrization mechanism — each case becomes an independent test
with a distinct name, runs even when siblings fail, and reports its own input on failure.

```python
# GOOD: parametrized — each case is independent and named
@pytest.mark.parametrize(
    "email,expected",
    [
        ("a@b.co",       True),
        ("no-at-sign",   False),
        ("trailing@",    False),
        ("multi@a@b.co", False),
    ],
)
def test_validate_email(email, expected):
    assert validate_email(email) == expected
```

```typescript
// GOOD: Vitest `test.each`
test.each([
  ['a@b.co',       true],
  ['no-at-sign',   false],
  ['trailing@',    false],
  ['multi@a@b.co', false],
] as const)('validates %s', (email, expected) => {
  expect(validateEmail(email)).toBe(expected);
});
```

```swift
// GOOD: Swift Testing parameterized test
@Test(arguments: [
    ("a@b.co",       true),
    ("no-at-sign",   false),
    ("trailing@",    false),
    ("multi@a@b.co", false),
])
func validateEmail(email: String, expected: Bool) {
    #expect(EmailValidator.isValid(email) == expected)
}
```

### Gate Function: Loop in a Test Body

```text
BEFORE writing `for case in cases:` inside a test:
  Ask: "Is this loop driving the same assertion with different inputs?"

  IF yes:
    STOP — parametrize instead
    Each case must:
      - be an independent test with its own name
      - run when sibling cases fail
      - report its own input on failure

  Exception: the loop is *part of the behavior under test*
  (e.g. asserting that `process()` emits items in order from a stream).
  In that case, the loop is the Act, not a test-dispatch mechanism.
```

## When Mocks Become Too Complex

**Warning signs:**

- Mock setup longer than test logic
- Mocking everything to make the test pass
- Mocks missing methods real components have
- Test breaks when the mock changes

**Ask yourself:** "Do we need to be using a mock here?"

**Consider:** Integration tests with real components are often simpler than complex mocks.

## Red Flags

- Can't explain why the mock is needed
- Mocking "just to be safe"
