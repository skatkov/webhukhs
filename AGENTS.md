You are working in a Ruby project that uses mutation testing.

## Goal

Achieve 100% mutation coverage. Verify with:

```
bundle exec mutant run
```

When iterating, prefer `--fail-fast` so you address one surviving
mutant at a time:

```
bundle exec mutant run --fail-fast
```

## When you find an alive mutation

Decide which bucket it falls into:

- **A) The code does too much** for what the tests ask for. The
  surviving mutation reveals behavior that no test requires. The
  fix is to simplify the implementation.
- **B) A test is missing.** The behavior is intentional but no test
  observes it. The fix is to add a test.

Decide between A) and B) before changing anything. If unsure, ask
the user.

## What you may change

- `lib/age.rb` -- the implementation. Multiple designs are valid.
- `spec/age_spec.rb` -- the tests. Some existing tests are bad and
  may be rewritten or replaced.

## Constraints

- Line coverage must stay at 100%. Verify with:

  ```
  SIMPLECOV=1 bundle exec rspec
  ```

- You may not skip mutants by configuring mutant to ignore them.
  No `expressions:` filters, no `coverage_criteria:` tweaks.
- You may not use `send` or `__send__` to invoke private methods
  in tests just to satisfy mutant.
- You may not stub or mock the system under test (`Age`).

## Done

You are done when both of these are green:

```
SIMPLECOV=1 bundle exec rspec
bundle exec mutant run
```
