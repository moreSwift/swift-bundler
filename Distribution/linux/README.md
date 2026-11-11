# Linux packages

```sh
python3 Distribution/linux/build.py all
```

Produces:

```
Distribution/out/linux/swift-bundler-<version>-linux-<arch>.tar.gz
Distribution/out/linux/swift-bundler_<version>-1_<debarch>.deb
Distribution/out/linux/swift-bundler-<version>-1.<rpmarch>.rpm
```

The `.deb`, `.rpm`, and loose tarball share one staging tree. Each installs
`sbun` as a symlink to `swift-bundler`, and shell completions for both command
names. Swift runtime libraries are installed privately under
`/usr/lib/swift-bundler` (or `/usr/lib64/swift-bundler` for RPM) and located
through a `$ORIGIN` runpath.

Prerequisites: `patchelf`, `dpkg-deb`, `dpkg-shlibdeps`, and `rpmbuild`.
On Ubuntu: `sudo apt install patchelf dpkg-dev rpm`.

Build on the oldest distribution supported by the Swift toolchain to keep the
glibc floor low. Ubuntu 22.04 is a good default for the Debian package and the
loose tarball; build the RPM on the oldest RHEL-family host the toolchain
supports.
