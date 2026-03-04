# Contributing

Contributions of all kinds are very welcome! Just make sure to follow the [guidelines](#guidelines) so that your pull requests have the best chance of being accepted.

## Getting started

1. Fork this repository
2. Clone your fork
3. Make changes
4. Open a pull request

## Guidelines

1. Indentation: 2 spaces per indent
2. Add comments to code that you think would need explaining to other contributors
3. Add/update documentation for any code you create/change
4. If a change can be made without introducing breaking changes, don't introduce breaking changes
5. Swift Bundler is programmed in a functional programming style, this means avoid global state and use static functions where possible. This is done to improve reusability of components and to make code easier to reason about
6. Use typed throws and `RichError` for error handling
7. Each utility should have its own error message type named `ErrorMessage` (unless it returns no errors)
8. Each utility that has an `ErrorMessage` type should have `typealias Error = RichError<ErrorMessage>`
9. Catch blocks should attach the underlying error to the thrown rich error via the `cause` parameter to form an error chain.
10. Errors should provide as much context as you think a user would need to understand what happened (if possible)

## Creating tests

### Creating and using test fixtures

1. Place the fixture in its own subdirectory of `Tests/SwiftBundlerTests/Fixtures`
2. (Optional): If the fixture is a Swift package that needs to depend on Swift Bundler
   (e.g. to use the runtime API or the builder API), then use a package dependency of
   the form `.package(path: "../swift-bundler/")`. This ensures that the fixture can
   both be built in isolation, and in temporary testing copies.
3. To use the fixture in a test, use the `withFixture` helper function. The helper
   function will create a temporary copy of the fixture in a system-dependent
   temporary directory and handles clean up after your test completes. It also ensures
   that there's a symlink to your Swift Bundler checkout present at `../swift-bundler/`
   relative to the fixture.

```swift
// Example usage of `withFixture`
withFixture("YourFixtureSubdirectoryName") { fixture in
  await SwiftBundler.main(["run", "-d", fixture.path])
}
```
