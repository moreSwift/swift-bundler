# Configuration

Configuring your app.

## Overview

Swift Bundler's configuration is stored in the `Bundler.toml` file in the root
directory of a package.

## Example configuration

Below is an example configuration containing all fields.

```toml
format_version = 2

# `HelloWorld` here is the app's name. Use double quotes if your app's name
# contains special characters such as spaces.
[apps.HelloWorld]
# The app's identifier, used by bundlers which require reverse domain name
# identifiers.
identifier = "com.example.HelloWorld"
# The SwiftPM package executable product to bundle
product = "HelloWorld"
# The app's version. Displayed on macOS's automatic 'About HelloWorld' screen.
version = "0.1.0"
# The app's description. Displayed by some package managers.
description = "A basic app."
# The license used by the app. Using SPDX identifiers is recommended.
license = "MIT"
# Only used by the Darwin bundler at the moment. Corresponds to Apple's category
# identifiers. See https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype
category = "public.app-category.education" # Optional
# The app's icon.
# Can be any of the following formats:
# - 1024x1024px PNG file (`.png`)
# - ICNS file (`.icns`) (Apple platforms only)
# - Icon Composer file (`.icon`) (Apple platforms only)
icon = "icon.png" # Optional
# Custom URL schemes supported by the app (for deep linking). Swift Bundler
# sets up the required metadata to get such URL schemes redirected to your
# app. It's up to your app to handle the different ways that platforms deliver
# custom URL events, or to use a cross platform framework such as SwiftCrossUI
# that can handle those differences on your behalf.
url_schemes = ["hello"]
# Build dependencies (outside of those handled by SwiftPM). Dependencies without
# dots are interpreted as executable products to include from the root SwiftPM
# package as helper executables (placed next to the main executable). Dependencies
# with a dot are interpreted as either library or executable products to include
# from a subproject. This allows pulling cmake dependencies into Swift Bundler
# projects. This is often used to pull in libsentry.
dependencies = ["Updater", "cmakeproj.hello"]

# Extra entries for your app's Info.plist file. Currently has no effect on
# Linux.
[apps.HelloWorld.plist]
# This could be any key-value pair, `CFBundleShortVersionString` is just an
# example. Patterns of the form `$(...)` get replaced with their corresponding
# values. See 'Variable substitutions' below.
CFBundleShortVersionString = "$(VERSION)_$(COMMIT_HASH)"

# Define platform-specific or bundler-specific configuration properties using
# conditional overlays.
[[apps.HelloWorld.overlays]]
condition = "platform(linux)"
# Generate a D-Bus service file for the app. This allows the app to handle URL
# schemes.
dbus_activatable = true
# You can also use overlays to provide platform-specific overrides for general
# configuration properties.
url_schemes = ["hello", "hello-linux"]

[[apps.HelloWorld.overlays]]
condition = "bundler(linuxRPM)"
# Specify external packages required by the app. This property is currently
# only available when using the linuxRPM bundler.
requirements = ["gtk3"]

[[apps.HelloWorld.overlays]]
condition = "platform(macCatalyst)"
# Specify the interface idiom used by the app when run under Mac Catalyst.
# Respected by UIKit. Value must be `ipad` (Scaled to Match iPad) or `mac`
# (Optimize for Mac).
interface_idiom = "mac"

# Subprojects are dependencies or constituent parts of a project that fall
# outside of the reign of SwiftPM. They can use custom builders and can build
# from either local or git sources.
[projects.cmakeproj]
# The subprojects source directory. Can be `local(...)` (a path) or
# `git(...)` (a git url). When using a `git` source, you must specify a
# revision via the separate `revision` config property.
source = "local(./cmakeproj)"

# All projects must define their own builders.
[projects.cmakeproj.builder]
# The name of the builder. This field is oddly named, but for now it's just the
# path to the builder's source file. Remote builder sources will eventually be
# supported (so that projects can vend builders for others to use).
name = "CMakeBuilder.swift"
# The type of builder. Currently `wholeProject` is the only option. That is,
# when invoked the builder must just build all required products.
type = "wholeProject"
# The revision of the Swift Bundler builder API to use when building the builder.
api = "revision(2cbe252923017306998297ee8bea817079a0eda4)"

# Projects can define as many products as they want. Library products are built
# and inserted into SwiftPM's build directory so that they can be found when
# the app's product gets built. All you need to do is include the header in your
# product and Swift Bundler makes sure that the linking just works. Executable
# products get included as helper executables next to the main executable
# (regardless of bundler). Overlays can be used to override `type` and
# `output_directory` depending on platform (see the overlay example for the
# HelloWorld app above).
[projects.cmakeproj.products.hello]
# The type of product. One of `dynamicLibrary`, `staticLibrary` or `executable`.
type = "dynamicLibrary"
# The directory within the build directory to look for the built product. Swift
# Bundler passes a build directory to the builder which the builder is expected
# to build into, but sometimes the products may exist within some sort of nested
# directory structure. Defaults to `.`
output_directory = "."
```
*Bundler.toml*

> Note: Only the `product`, `version` and `identifier` fields are required.

For the sake of completeness, here's the source code for the `CMakeBuilder.swift`
referred to by the example configuration.

```swift
import SwiftBundlerBuilders

@main
struct CMakeBuilder: Builder {
    static func build(_ context: some BuilderContext) async throws -> BuilderResult {
        try await context.run(
            "cmake",
            ["-B", context.buildDirectory.path]
        )
        try await context.run(
            "cmake",
            ["--build", context.buildDirectory.path, "--target", "hello"]
        )
        return BuilderResult()
    }
}
```
*CMakeBuilder.swift*

## Schema

Some editors allow JSON schemas to be used when editing TOML files. If you're
using such an editor, Swift Bundler has a [Bundler.schema.json](https://github.com/moreSwift/swift-bundler/blob/main/Bundler.schema.json)
schema file describing the `Bundler.toml` format.

If the schema is ever outdated, you can use [generate_schema.sh](https://github.com/moreSwift/swift-bundler/blob/main/generate_schema.sh)
to generate the schema from the Swift Bundler source code as a quick fix, but
make sure to let me know anyway so that I can update it for everyone!

## App Icons

To add an icon to your app, provide a value for the `icon` field of your app's
configuration.

Icons can be provided in any of the following formats:
- 1024x1024px PNG file (`.png`)
- ICNS file (`.icns`) (Apple platforms only)
- Icon Composer file (`.icon`) (Apple platforms only)

Overlays can be used to specify an ICNS or Icon Composer icons on Apple platforms
only:

```toml
[apps.Example]
icon = "AppIcon.png"

[[apps.Example.overlays]]
condition = "platform(macOS)"
icon = "AppIcon.icon"
```

The easiest method to create an `icns` file is to create an `iconset` using Xcode
and then convert it using the following command:

```sh
/usr/bin/iconutil -c icns /path/to/AppIcon.iconset
```

## Info.plist customization

If you want to add extra key-value pairs to your app's `Info.plist`, you can
specify them in the app's `plist` field. Here's an example configuration that
appends the current commit hash to the version string displayed in the
`About HelloWorld` screen of the `HelloWorld` app.

```toml
# ...
[apps.HelloWorld.plist]
CFBundleShortVersionString = "$(VERSION)_$(COMMIT_HASH)"
```

Patterns of the form `$(...)` get replaced with their corresponding values. See
[Variable substitutions](#Variable-substitutions) below.

If you provide a value for a key that is already present in the default
`Info.plist`, the default value will be overidden with the value you provide.

### Type ambiguity

Certain Property List field types such as `data`, `date`, and `integer` can't be
distinguished using TOML syntax alone. Swift Bundler will throw an error if any
values cannot be decoded unambiguosly.

To disambiguate, you can convert the value to a TOML dictionary with separate
`type` and `value` fields. For this reason, dictionaries with a `type` field
also require disambiguation.

Property List field type | Requires disambiguation? | Example
-----------|---------------------|----------------------
`string` | no | `MyKey = "My string"`
`boolean` | no | `MyKey = true`
`array` | no | `MyKey = [1, "A string"]`
`real` | no, *unless a whole number* | `MyKey = 1.2` or `MyKey = { type = "real", value = 1.0 }`
`integer` | no | `MyKey = 1`
`date` | **yes** | `MyKey = { type = "date", value = "2024-12-02T10:08:00Z" }`
`data` | **yes** | `MyKey = { type = "data", value = "b3R0ZXIncyBpbiBhIHN0YWNrPw==" }`, must be base64 encoded
`dict` | no, *unless it contains a `type` key* | `MyKey = { major = 1, minor = 0 }` or `MyKey = { type = "dict", value = { type = 1, tag = 0 } }`

## Multi-app packages

Swift Bundler makes it trivial to create multiple apps from one package. Here's
an example configuration with a main app and an updater app.

```toml
[apps.Example]
identifier = "com.example.Example"
product = "Example"
version = "0.1.0"

[apps.Updater]
identifier = "com.example.Updater"
product = "Updater"
version = "1.0.1"
```

Once multiple apps are defined, certain commands such as `run` and `bundle`
require an app name in order to know which app to operate on.

```sh
# Run the main app.
swift bundler run Example
# Run the updater.
swift bundler run Updater
```

## Variable substitutions

Some configuration fields (currently only `plist`) support variable
substitution. This means that anything of the form `$(VARIABLE)` within the
field's value will be replaced by the variable's value. Below is a list of all
supported variables.

Name | Value
-----|------
`VERSION` | The app's version
`COMMIT_HASH` | The commit hash of the git repository at the package's root directory. If there is no git repository, an error will be thrown.
