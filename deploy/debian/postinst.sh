#!/bin/bash
#
# Generic Debian postinst for Webitel Go services.
#
# Managed centrally in webitel/reusable-configs and synced verbatim into each
# service repo at deploy/debian/postinst.sh — DO NOT edit per-repo.
#
# It is service-agnostic:
#   * the systemd units to manage are discovered at runtime from the package
#     itself, so it works for single- and multi-unit packages alike;
#   * service-specific setup (e.g. creating data dirs or certificates) is
#     provided by the package as drop-in hooks (see run_postinst_hooks).

set -e

USER_NAME="webitel"
GROUP_NAME="webitel"

have_systemctl() {
    command -v systemctl >/dev/null 2>&1
}

# systemd unit files shipped by THIS package, as basenames
# (e.g. "webitel-engine.service"). Empty if the package ships no units.
package_units() {
    dpkg-query -L "$DPKG_MAINTSCRIPT_PACKAGE" 2>/dev/null \
        | grep -E '/systemd/system/[^/]+\.service$' \
        | sed 's:.*/::'
}

create_user() {
    if ! getent group "$GROUP_NAME" >/dev/null 2>&1; then
        echo "Creating group: $GROUP_NAME"
        addgroup --system "$GROUP_NAME"
    fi

    if ! getent passwd "$USER_NAME" >/dev/null 2>&1; then
        echo "Creating user: $USER_NAME"
        adduser --system --no-create-home --ingroup "$GROUP_NAME" \
                --disabled-password --disabled-login \
                --shell /bin/false \
                --gecos "Webitel service user" \
                "$USER_NAME"
    fi
}

# Run service-specific setup shipped by the package, BEFORE any unit is
# enabled or started. Hooks are sourced (they see the script's environment)
# and run under `set -e`: a failing hook aborts the install, which is the
# correct behaviour when e.g. a required certificate cannot be generated.
run_postinst_hooks() {
    local hook_dir="/usr/lib/$DPKG_MAINTSCRIPT_PACKAGE/deb/postinst.d"
    [ -d "$hook_dir" ] || return 0

    local hook
    for hook in "$hook_dir"/*; do
        [ -f "$hook" ] || continue
        echo "Running postinst hook: $hook"
        # shellcheck disable=SC1090
        . "$hook"
    done
}

if [ "$1" = "configure" ]; then
    echo "Configuring $DPKG_MAINTSCRIPT_PACKAGE..."

    create_user
    run_postinst_hooks

    if have_systemctl; then
        systemctl daemon-reload

        units=$(package_units)

        if [ -z "$2" ]; then
            # Fresh install: enable units for boot but do NOT start them.
            # The shipped configuration usually contains placeholder values,
            # so the operator must review it before the first start.
            for unit in $units; do
                systemctl enable "$unit" || true
            done

            echo "$DPKG_MAINTSCRIPT_PACKAGE installed and enabled (not started)."
            if [ -n "$units" ]; then
                echo ""
                echo "Next steps:"
                echo "1. Review configuration under /etc/systemd/system/ and /etc/default/"
                echo "2. Start:  sudo systemctl start $units"
                echo "3. Status: sudo systemctl status $units"
            fi
        else
            # Upgrade: restart only units that were running, so a deliberately
            # stopped service stays stopped while a running one picks up the
            # new binary.
            for unit in $units; do
                echo "Restarting $unit (if running)..."
                systemctl try-restart "$unit" || true
            done
        fi
    fi
fi

exit 0
