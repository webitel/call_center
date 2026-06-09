#!/bin/bash
#
# Generic Debian prerm for Webitel Go services.
#
# Managed centrally in webitel/reusable-configs and synced verbatim into each
# service repo at deploy/debian/prerm.sh — DO NOT edit per-repo.
#
# Stops (and, on full removal, disables) every systemd unit shipped by the
# package. Units are discovered at runtime, so this works for single- and
# multi-unit packages alike.

set -e

have_systemctl() {
    command -v systemctl >/dev/null 2>&1
}

# systemd unit files shipped by THIS package, as basenames.
package_units() {
    dpkg-query -L "$DPKG_MAINTSCRIPT_PACKAGE" 2>/dev/null \
        | grep -E '/systemd/system/[^/]+\.service$' \
        | sed 's:.*/::'
}

stop_units() {
    have_systemctl || return 0

    local unit
    for unit in $(package_units); do
        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            echo "Stopping $unit..."
            # systemctl stop is synchronous and enforces the unit's
            # TimeoutStopSec (escalating to SIGKILL) on its own.
            systemctl stop "$unit" || true
        fi
    done
}

disable_units() {
    have_systemctl || return 0

    local unit
    for unit in $(package_units); do
        if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            echo "Disabling $unit..."
            systemctl disable "$unit" || true
        fi
    done
}

case "$1" in
    remove)
        echo "Removing $DPKG_MAINTSCRIPT_PACKAGE..."
        stop_units
        disable_units
        ;;

    deconfigure|failed-upgrade)
        # Stop but keep the unit enabled.
        stop_units
        ;;
esac

exit 0
