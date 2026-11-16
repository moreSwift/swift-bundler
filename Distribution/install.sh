#!/usr/bin/env bash
# Installs Swift Bundler from the artifacts attached to a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/moreSwift/swift-bundler/main/install.sh | bash
#
# macOS installs the universal .pkg, Linux installs the .deb or .rpm. Pass
# --prefix to install without root: macOS uses the standalone universal binary
# and Linux uses the loose tarball.
set -eu

REPOSITORY="${SWIFT_BUNDLER_REPOSITORY:-moreSwift/swift-bundler}"
API_URL="${SWIFT_BUNDLER_API_URL:-https://api.github.com/repos/${REPOSITORY}/releases/latest}"
DOWNLOAD_URL="${SWIFT_BUNDLER_DOWNLOAD_URL:-https://github.com/${REPOSITORY}/releases/download}"
VERSION="${SWIFT_BUNDLER_VERSION:-}"
PREFIX="${SWIFT_BUNDLER_PREFIX:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Installs Swift Bundler from the latest GitHub release.

Options:
  -v, --version <version>  Install a specific version (default: latest)
  -p, --prefix <dir>       Install without root into <dir>
                           (macOS: standalone binary, Linux: loose tarball)
      --dry-run            Print what would be done without doing it
  -h, --help               Show this help

Environment:
  SWIFT_BUNDLER_VERSION, SWIFT_BUNDLER_PREFIX
  SWIFT_BUNDLER_REPOSITORY    Repository to install from
                              (default: moreSwift/swift-bundler)
  SWIFT_BUNDLER_API_URL       "Latest release" endpoint
  SWIFT_BUNDLER_DOWNLOAD_URL  Release download base URL
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v | --version)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      VERSION="$2"
      shift 2
      ;;
    -p | --prefix)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      PREFIX="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  *) fail "unsupported operating system: $(uname -s)" ;;
esac

case "$(uname -m)" in
  x86_64 | amd64)
    ARCH=x86_64
    DEB_ARCH=amd64
    RPM_ARCH=x86_64
    ;;
  arm64 | aarch64)
    ARCH=arm64
    DEB_ARCH=arm64
    RPM_ARCH=aarch64
    ;;
  *) fail "unsupported architecture: $(uname -m)" ;;
esac

http_get() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    fail "curl or wget is required"
  fi
}

http_get_stdout() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 "$1"
  else
    wget -q -O - "$1"
  fi
}

parse_tag() {
  sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

if [ -z "$VERSION" ]; then
  log "Looking up the latest release of $REPOSITORY"
  TAG="$(http_get_stdout "$API_URL" | parse_tag)"
  [ -n "$TAG" ] || fail "could not determine the latest release from $API_URL"
else
  case "$VERSION" in
    v*) TAG="$VERSION" ;;
    *) TAG="v$VERSION" ;;
  esac
fi
VERSION="${TAG#v}"

# Work out which artifact this machine needs and how it will be installed.
MODE=""
ASSET=""
DESCRIPTION=""
NEEDS_ROOT=0

if [ "$OS" = "macos" ]; then
  if [ -n "$PREFIX" ]; then
    MODE=macos-binary
    ASSET="swift-bundler-$VERSION-macos-universal"
    DESCRIPTION="standalone universal binary in $PREFIX/bin"
  else
    MODE=macos-pkg
    ASSET="swift-bundler-$VERSION-macos-universal.pkg"
    DESCRIPTION="universal .pkg installer (requires root)"
    NEEDS_ROOT=1
  fi
elif [ -n "$PREFIX" ]; then
  MODE=linux-tarball
  ASSET="swift-bundler-$VERSION-linux-$ARCH.tar.gz"
  DESCRIPTION="loose tarball in $PREFIX"
elif command -v dpkg >/dev/null 2>&1; then
  MODE=linux-deb
  ASSET="swift-bundler_${VERSION}-1_${DEB_ARCH}.deb"
  DESCRIPTION=".deb package (requires root)"
  NEEDS_ROOT=1
elif command -v rpm >/dev/null 2>&1; then
  MODE=linux-rpm
  ASSET="swift-bundler-${VERSION}-1.${RPM_ARCH}.rpm"
  DESCRIPTION=".rpm package (requires root)"
  NEEDS_ROOT=1
else
  MODE=linux-tarball
  PREFIX=/usr/local
  ASSET="swift-bundler-$VERSION-linux-$ARCH.tar.gz"
  DESCRIPTION="loose tarball in $PREFIX (requires root)"
  NEEDS_ROOT=1
fi

URL="$DOWNLOAD_URL/$TAG/$ASSET"

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<EOF
Swift Bundler $VERSION
  asset:    $ASSET
  url:      $URL
  method:   $DESCRIPTION
EOF
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

verify_checksum() {
  local file="$1"
  local directory
  directory="$(dirname "$file")"
  if command -v shasum >/dev/null 2>&1; then
    (cd "$directory" && shasum -a 256 -c "$(basename "$file").sha256")
  elif command -v sha256sum >/dev/null 2>&1; then
    (cd "$directory" && sha256sum -c "$(basename "$file").sha256")
  else
    log "warning: no shasum or sha256sum; skipping checksum verification"
  fi
}

download() {
  local asset="$1"
  log "Downloading $URL"
  if ! http_get "$URL" "$TMP/$asset"; then
    fail "failed to download $URL (does release $TAG publish $asset?)"
  fi
  if http_get "$URL.sha256" "$TMP/$asset.sha256" 2>/dev/null; then
    verify_checksum "$TMP/$asset"
  fi
}

# Runs an installation command, escalating only when the selected method
# installs into a location that needs root (never for --prefix installs).
run_install() {
  if [ "$(id -u)" -eq 0 ] || [ "$NEEDS_ROOT" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_completions() {
  local binary="$1"
  local prefix="$2"
  local shell destination name contents
  for shell in bash zsh fish; do
    case "$shell" in
      bash)
        destination="$prefix/share/bash-completion/completions"
        name="swift-bundler"
        alias_name="sbun"
        ;;
      zsh)
        destination="$prefix/share/zsh/site-functions"
        name="_swift-bundler"
        alias_name="_sbun"
        ;;
      fish)
        destination="$prefix/share/fish/vendor_completions.d"
        name="swift-bundler.fish"
        alias_name="sbun.fish"
        ;;
    esac
    mkdir -p "$destination"
    contents="$("$binary" --generate-completion-script "$shell")"
    printf '%s\n' "$contents" >"$destination/$name"
    printf '%s\n' "$contents" |
      sed 's/swift-bundler/sbun/g' >"$destination/$alias_name"
  done
}

download "$ASSET"

case "$MODE" in
  macos-binary)
    mkdir -p "$PREFIX/bin"
    install -m 0755 "$TMP/$ASSET" "$PREFIX/bin/swift-bundler"
    ln -sf swift-bundler "$PREFIX/bin/sbun"
    install_completions "$PREFIX/bin/swift-bundler" "$PREFIX"
    "$PREFIX/bin/swift-bundler" --version
    log "Installed Swift Bundler $VERSION to $PREFIX/bin"
    ;;
  macos-pkg)
    run_install installer -pkg "$TMP/$ASSET" -target /
    /usr/local/bin/swift-bundler --version
    log "Installed Swift Bundler $VERSION"
    ;;
  linux-deb)
    run_install dpkg -i "$TMP/$ASSET"
    /usr/bin/swift-bundler --version
    log "Installed Swift Bundler $VERSION"
    ;;
  linux-rpm)
    run_install rpm -i "$TMP/$ASSET" || run_install rpm -U "$TMP/$ASSET"
    /usr/bin/swift-bundler --version
    log "Installed Swift Bundler $VERSION"
    ;;
  linux-tarball)
    tar -xzf "$TMP/$ASSET" -C "$TMP"
    ROOT="$TMP/swift-bundler-$VERSION-linux-$ARCH"
    run_install mkdir -p "$PREFIX/bin" "$PREFIX/share"
    run_install cp -a "$ROOT/bin/." "$PREFIX/bin/"
    run_install cp -a "$ROOT/share/." "$PREFIX/share/"
    log "Installed Swift Bundler $VERSION to $PREFIX/bin"
    ;;
esac

case ":$PATH:" in
  *":${PREFIX:-/usr/local}/bin:"*) ;;
  *)
    if [ -n "$PREFIX" ]; then
      log "Add $PREFIX/bin to PATH to run 'swift-bundler' or 'sbun'."
    fi
    ;;
esac
