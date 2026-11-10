# Third-Party Notices

Swift Bundler itself is licensed under the MIT License (see `LICENSE`).

## Swift runtime

This distribution bundles dynamic libraries from the Swift runtime so that the
`swift-bundler` executable does not depend on the exact Swift toolchain that was
used to build it. The Swift runtime is distributed under the Apache License 2.0
with the Swift Runtime Library Exception.

The canonical license text is available in the Swift source repository:

- https://github.com/swiftlang/swift/blob/main/LICENSE.txt

Copyright © 2014-2026 the Swift project authors. All rights reserved.

## System libraries

Libraries that belong to the host system ABI (libc, libm, libpthread, libdl,
librt, libgcc_s, libstdc++, and the dynamic loader) are not redistributed. They
are provided by the operating system and are declared as package dependencies.
