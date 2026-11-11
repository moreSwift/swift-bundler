# Third-Party Notices

Swift Bundler itself is licensed under the MIT License (see `LICENSE`).

## Static Swift Linux SDK

This distribution was built with the Static Swift Linux SDK. The executable is
fully statically linked: it does not load a Swift runtime, C library, or other
system libraries at runtime.

Components statically linked into the executable may include:

- **Swift runtime** — Apache License 2.0 with the Swift Runtime Library Exception.
  https://github.com/swiftlang/swift/blob/main/LICENSE.txt
- **musl libc** — MIT License.
  https://musl.libc.org/license.html
- **curl** — curl License (MIT-like).
  https://curl.se/docs/copyright.html
- **libxml2** — MIT License.
  https://gitlab.gnome.org/GNOME/libxml2/-/blob/master/Copyright
- **zlib** — zlib License.
  https://zlib.net/zlib_license.html

Copyright notices and full license texts for these components are available
from the upstream projects linked above and from the Static Swift Linux SDK
artifact used to build this package.

## System libraries

No system libraries are required at runtime. The Linux kernel system call
interface is the only operating-system dependency.
