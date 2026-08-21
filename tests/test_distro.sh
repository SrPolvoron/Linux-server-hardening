#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/distro.sh"

tmp="$(mktemp -d)"; old_path="$PATH"; trap 'PATH="$old_path"; rm -rf "$tmp"' EXIT

write_os() {
  local id="$1" like="$2"
  cat > "$tmp/os-release" <<EOT
ID=$id
ID_LIKE="$like"
VERSION_ID=99
PRETTY_NAME="test $id"
EOT
  OS_RELEASE_FILE="$tmp/os-release"
}

write_os ubuntu debian
detect_distro
[[ "$DISTRO_FAMILY" == debian && "$PACKAGE_MANAGER" == apt ]]

write_os debian ''
detect_distro
[[ "$DISTRO_FAMILY" == debian && "$PACKAGE_MANAGER" == apt ]]

# Regression test: even when apt-get exists, an AlmaLinux/RHEL family host must
# select dnf by family, not by binary precedence.
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$tmp/bin/dnf"
printf '#!/usr/bin/env sh\nexit 0\n' > "$tmp/bin/apt-get"
chmod +x "$tmp/bin/dnf" "$tmp/bin/apt-get"
PATH="$tmp/bin:$old_path"
write_os almalinux 'rhel centos fedora'
detect_distro
[[ "$DISTRO_FAMILY" == rhel && "$PACKAGE_MANAGER" == dnf ]]

write_os rocky 'rhel centos fedora'
detect_distro
[[ "$DISTRO_FAMILY" == rhel && "$PACKAGE_MANAGER" == dnf ]]

echo "test_distro: OK"
