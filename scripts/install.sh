#!/bin/sh
# Install a prebuilt Linux binary into KryptOS or a staged root.
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: DESTDIR=/staging/root scripts/install.sh /path/to/axon-binary" >&2
    exit 2
fi
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dest=${DESTDIR:-}
binary=$1
[ -f "$binary" ] && [ -x "$binary" ] || {
    echo "axon: executable binary missing: $binary" >&2
    exit 1
}
install -d "$dest/usr/bin" "$dest/usr/local/libexec" "$dest/etc/pam.d"
install -m755 "$binary" "$dest/usr/bin/axon"
install -m755 "$src/libexec/axon-pam" "$dest/usr/local/libexec/axon-pam"
install -m644 "$src/pam.d/axon" "$dest/etc/pam.d/axon"
install -m644 "$src/pam.d/axon-autologin" "$dest/etc/pam.d/axon-autologin"
install -d -m755 "$dest/etc/axon"
# Preserve configuration and leave KryptOS's existing DM dispatcher intact.
if [ ! -e "$dest/etc/axon/config" ]; then
    printf '%s\n' 'animation=unimatrix' 'save_session=on' > "$dest/etc/axon/config"
    chmod 600 "$dest/etc/axon/config"
fi
