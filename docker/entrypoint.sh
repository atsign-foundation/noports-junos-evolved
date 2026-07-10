#!/usr/bin/env bash
# Entrypoint for the NoPorts container on Junos OS Evolved.
#
# Configuration comes from environment variables, normally supplied with
# `docker run --env-file /var/extensions/noports/noports.env` (see
# noports.env.example at the repo root):
#
#   DEVICE_ATSIGN   (required)  atSign identifying this router, e.g. @mydevice
#   DEVICE_NAME     (required)  device name clients use: sshnp -d <name>
#   MANAGER_ATSIGN  (*)         atSign(s) allowed to connect; comma-separated
#   POLICY_ATSIGN   (*)         atSign of a NoPorts Policy Service deciding
#                               access requests centrally — the right choice
#                               for large fleets; if both are set, atSigns
#                               in MANAGER_ATSIGN bypass the policy check
#                               (*) at least one of the two is required
#   ROOT_SERVER     (optional)  atDirectory; default root.atsign.org.
#                               Use proxy:proxy0001.atsign.org:443 when
#                               management-plane ACLs restrict egress.
#   PERMIT_OPEN     (optional)  comma-separated host:port list clients may
#                               reach; default localhost:22
#   SSHD_PORT       (optional)  port the Junos ssh service listens on (22)
#   SSHNPD_EXTRA_ARGS (optional) extra raw flags appended to sshnpd
#
# APKAM atKeys are expected in $NOPORTS_KEYS_DIR (bind-mounted from
# /var/extensions/noports/keys on the routing engine). Until they exist the
# entrypoint waits and prints onboarding instructions — run
# onboard-noports.sh inside this container to enroll (see QUICKSTART.md).
set -euo pipefail

NOPORTS_KEYS_DIR="${NOPORTS_KEYS_DIR:-/atsign/keys}"
ROOT_SERVER="${ROOT_SERVER:-root.atsign.org}"
# Without a policy service, default to sshd only; with one, leave
# PERMIT_OPEN unset so sshnpd defers port restrictions to policy (*:*).
if [ -z "${PERMIT_OPEN:-}" ] && [ -z "${POLICY_ATSIGN:-}" ]; then
    PERMIT_OPEN="localhost:22"
fi
SSHD_PORT="${SSHD_PORT:-22}"

# sshnpd requires $USER in the environment; docker does not set it.
USER="${USER:-$(whoami)}"
export USER

fail=0
for var in DEVICE_ATSIGN DEVICE_NAME; do
    if [ -z "${!var:-}" ]; then
        echo "noports: required environment variable $var is not set" >&2
        fail=1
    fi
done
if [ -z "${MANAGER_ATSIGN:-}" ] && [ -z "${POLICY_ATSIGN:-}" ]; then
    echo "noports: at least one of MANAGER_ATSIGN / POLICY_ATSIGN must be set" >&2
    fail=1
fi
if [ "$fail" -ne 0 ]; then
    echo "noports: set it in /var/extensions/noports/noports.env on the" >&2
    echo "noports: routing engine and restart the container:" >&2
    echo "noports:   docker restart noports" >&2
    exit 1
fi

case "$DEVICE_ATSIGN" in
    @*) ;;
    *) DEVICE_ATSIGN="@${DEVICE_ATSIGN}" ;;
esac

KEY_FILE="${NOPORTS_KEYS_DIR}/${DEVICE_ATSIGN}_key.atKeys"
mkdir -p "$NOPORTS_KEYS_DIR"

# Wait for onboarding: the device atKeys are cut on-box by APKAM enrollment
# (onboard-noports.sh) and land on the persistent bind mount.
while [ ! -f "$KEY_FILE" ]; do
    echo "noports: waiting for atKeys at ${KEY_FILE}"
    echo "noports: device not yet onboarded. From the Junos shell run:"
    echo "noports:   docker exec -it noports onboard-noports.sh <passcode>"
    echo "noports: (generate the passcode on your admin machine with:"
    echo "noports:   at_activate otp -a ${DEVICE_ATSIGN} )"
    sleep 30
done

echo "noports: atKeys found; starting sshnpd (device ${DEVICE_NAME})"

ACCESS_ARGS=()
if [ -n "${MANAGER_ATSIGN:-}" ]; then
    ACCESS_ARGS+=(--managers "$MANAGER_ATSIGN")
fi
if [ -n "${POLICY_ATSIGN:-}" ]; then
    ACCESS_ARGS+=(--policy-manager "$POLICY_ATSIGN")
fi
if [ -n "${PERMIT_OPEN:-}" ]; then
    ACCESS_ARGS+=(--permit-open "$PERMIT_OPEN")
fi

# Word-splitting of SSHNPD_EXTRA_ARGS is intentional.
# shellcheck disable=SC2086
exec /usr/local/bin/sshnpd \
    --atsign "$DEVICE_ATSIGN" \
    "${ACCESS_ARGS[@]}" \
    --device "$DEVICE_NAME" \
    --key-file "$KEY_FILE" \
    --root-server "$ROOT_SERVER" \
    --local-sshd-port "$SSHD_PORT" \
    --storage-path /atsign/storage \
    --verbose \
    ${SSHNPD_EXTRA_ARGS:-}
