# Migrating projects to Swift Bundler

A quick guide on migrating projects from other build systems to Swift Bundler.

## Adding Swift Bundler support to a SwiftPM project

Swift Bundler is built on top of SwiftPM, so if you have a SwiftPM package then you're already most of the way to having a Swift Bundler project.

All you have to do is create a `Bundler.toml` file describing the application that you'd like Swift Bundler to build. I've included a minimal `Bundler.toml` file below.

```toml
format_version = 2

[apps.MyApp]
# The product field tells Swift Bundler which SwiftPM executable product to
# build as your app's main executable.
product = "MyApp"
identifier = "com.example.MyApp"
version = "0.1.0"
```

The <doc:configuration> article explains all of the available configuration options in case you're interested.

## Migrating from xcodeproj to Swift Bundler

Swift Bundler has an experimental `convert` command that can be used to convert xcodeprojs and xcworkspaces to Swift Bundler projects.

```sh
swift-bundler convert ./MyProject.xcodeproj --out ./MySwiftBundlerProject
cd MySwiftBundlerProject
```

Please note that the `convert` command is very experimental, and its output often requires manual fix ups to get your app compiling as intended, but it should generally provide a good starting point if it manages to parse and understand your project.

To test out whether your migration has succeeded, try running your app, and loop until you've fixed all of the issues.

```sh
# Run your app (make sure to execute this inside the output directory you gave
# to the convert command)
swift-bundler run
```

## Migrating from arbitrary build systems to Swift Bundler

If you're not using Xcode and you're not using SwiftPM then you'll be a bit more on your own.

Our recommended approach is to first convert your project into a SwiftPM package, and then follow the SwiftPM instructions in the section above.

Alternatively, you can create a new Swift Bundler project with `swift-bundler create MyProject --template SwiftCrossUI` and then copy your code across to the new project, but that is perhaps more disruptive if you're only wanting to try out hot reloading.
