# Package templates

Easily create common types of apps from templates.

## Overview

Package templates reduce the amount of boiler plate code you have to replicate when creating a new project.

## Default templates

Swift Bundler comes with a few useful templates by default. Use the following command to list them:

```sh
swift-bundler template ls
```

The default templates are located at `~/Library/Application Support/dev.stackotter.swift-bundler/templates` and are downloaded from [the swift-bundler-templates repository](https://github.com/moreSwift/swift-bundler-templates) when the first command requiring templates is run.

Use the following command to get more information about each template:

```sh
swift-bundler template info [template]
```

Once you have decided which template you want to use, you can create a package from the template:

```sh
swift-bundler create [app-name] --identifier [app-identifier] --template [template]
```

## Custom templates

It's relatively easy to create custom templates for Swift Bundler. See <doc:custom-templates> to learn more.

## Troubleshooting

If you run into issues relating to templates, you may want to try updating the default templates:

```sh
swift-bundler template update
```
