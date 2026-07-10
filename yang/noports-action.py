#!/usr/bin/env python3
"""EXPERIMENTAL — Phase 2 scaffolding, not yet wired up or validated.

Skeleton Junos YANG action/translation script for the NoPorts custom YANG
package (yang/noports.yang). Loaded together with the module via:

    request system yang add package noports module noports.yang \
        action-script noports-action.py

Junos OS Evolved executes YANG action and translation scripts with Python 3
since release 22.3R1 (earlier releases used Python 2.7):
https://www.juniper.net/documentation/us/en/software/junos/netconf/topics/task/netconf-yang-scripts-action-creating.html

Intended behavior once wired up (mirroring the SR Linux NDK agent):

1. On commit, receive the candidate `noports` configuration subtree.
2. Render /var/extensions/noports/noports.env from it (the same env file
   the container entrypoint consumes — see noports.env.example).
3. Restart the noports container so sshnpd picks up the new settings
   (`docker restart noports`), or render config/sshnpd.yaml and use
   `sshnpd --config` instead of env vars.

Unsigned Python scripts require:
    set system scripts language python3
and (device dependent) permitting unsigned scripts. TODO-verify the exact
statements required on Junos OS Evolved before wiring this up.
"""

import os
import subprocess
import sys

# Junos-only modules; unavailable off-box (e.g. in CI syntax checks).
try:
    from junos import Junos_Configuration  # type: ignore  # noqa: F401
    import jcs  # type: ignore
except ImportError:
    jcs = None

ENV_FILE = "/var/extensions/noports/noports.env"
CONTAINER_NAME = "noports"


def emit(msg: str) -> None:
    """Log via jcs on-box, stderr elsewhere."""
    if jcs is not None:
        jcs.syslog("external.info", f"noports: {msg}")
    else:
        print(f"noports: {msg}", file=sys.stderr)


def read_noports_config() -> dict:
    """Extract the `noports` subtree from the committed configuration.

    TODO: implement. On-box options include walking Junos_Configuration
    (lxml element of the post-inheritance candidate config) or invoking
    <get-configuration> via jcs. Returns the leaf values keyed by the env
    var names the container entrypoint expects.
    """
    raise NotImplementedError("Phase 2: config extraction not implemented")


def render_env_file(cfg: dict) -> None:
    """Render the container env file from the config subtree."""
    lines = [
        "# Rendered by the noports YANG action script — do not edit;",
        "# change `set noports ...` in the Junos config and commit instead.",
        f"DEVICE_ATSIGN={cfg['device_atsign']}",
        f"MANAGER_ATSIGN={','.join(cfg['manager_atsigns'])}",
        f"DEVICE_NAME={cfg['device_name']}",
    ]
    if cfg.get("root_server"):
        lines.append(f"ROOT_SERVER={cfg['root_server']}")
    if cfg.get("permit_open"):
        lines.append(f"PERMIT_OPEN={','.join(cfg['permit_open'])}")
    os.makedirs(os.path.dirname(ENV_FILE), exist_ok=True)
    with open(ENV_FILE, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    emit(f"rendered {ENV_FILE}")


def restart_container() -> None:
    """Bounce the noports container so sshnpd picks up the new env file."""
    subprocess.run(["docker", "restart", CONTAINER_NAME], check=True)
    emit(f"restarted container {CONTAINER_NAME}")


def main() -> int:
    emit("action script invoked (Phase 2 scaffold — not implemented)")
    try:
        cfg = read_noports_config()
    except NotImplementedError as exc:
        emit(str(exc))
        return 1
    render_env_file(cfg)
    restart_container()
    return 0


if __name__ == "__main__":
    sys.exit(main())
