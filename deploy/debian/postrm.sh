#!/bin/bash
#
# Generic Debian postrm for Webitel Go services.
#
# Managed centrally in webitel/reusable-configs and synced verbatim into each
# service repo at deploy/debian/postrm.sh — DO NOT edit per-repo.
#
# After the unit files have been removed from disk, tell systemd to forget
# them and clear any leftover failed state. Service data (e.g. storage
# recordings/certificates) is intentionally NOT removed on purge.

set -e

have_systemctl() {
    command -v systemctl >/dev/null 2>&1
}

# systemd unit files recorded for THIS package, as basenames. dpkg still
# knows the file list at postrm/remove time even though the files are gone.
package_units() {
    dpkg-query -L "$DPKG_MAINTSCRIPT_PACKAGE" 2>/dev/null \
        | grep -E '/systemd/system/[^/]+\.service$' \
        | sed 's:.*/::'
}

if [ "$1" = "remove" ]; then
    if have_systemctl; then
        systemctl daemon-reload || true

        for unit in $(package_units); do
            systemctl reset-failed "$unit" 2>/dev/null || true
        done
    fi
fi

exit 0
