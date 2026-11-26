# Custom templates

Custom templates are a great way to tailor Swift Bundler to your workflow.

## Overview

Making custom templates isn't too complicated, and after reading this page you should be able to easily create templates for all your needs. If you create a template that you think many users would find useful, feel free to open a PR at [the swift-bundler-templates repository](https://github.com/moreSwift/swift-bundler-templates) to add it to the default set of templates.

## Creating a custom template

1. Create a new template 'repository' (a directory that will contain a collection of templates)
2. Create a directory inside the template repository. The name of the directory is the name of your template. (`Base` is a reserved name, and the directory must not start with a `.`)
3. Create a `Template.toml` file (inside the template directory) with the following contents:

```toml
description = "My first package template."
platforms = ["macOS", "iOS"] # Adjust according to your needs, valid values are currently `macOS` and `iOS`
```
4. Add files to the template (see below for details)

Any files within the template directory (excluding `Template.toml`) are copied to the output directory when creating a package. Any occurrence of `{{VARIABLE}}` within the file's relative path is replaced with the corresponding variable's value. Any occurrence of `{{VARIABLE}}` within the contents of files ending with `.template` is replaced with the corresponding variable's value and the `.template` file extension is removed. The available variables are `PACKAGE` (the package's name) and `IDENTIFIER` (the package's identifier).

**All indentation must be tabs (not spaces) so that the `create` command's `--indentation` option functions correctly.**

You can also create a `Base` directory within the template repository. Whenever creating a new package, the `Base` directory is applied first and should contain the common files between all templates, such as the `.gitignore` file. A template can override files in the `Base` template by containing files of the same name.

See [the swift-bundler-templates repository](https://github.com/moreSwift/swift-bundler-templates) for some example templates.

## Using a custom template repository

```sh
sbun create MyApp --template MyTemplate --template-repository /path/to/TemplateRepository
```
