<!-- pyml disable-num-lines 4 md013,md033-->
<h1><a href="https://atsign.com#gh-light-mode-only">
   <img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a>
<a href="https://atsign.com#gh-dark-mode-only">
   <img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a></h1>

# NoPorts for Juniper Junos OS Evolved

Open with intent - we welcome contributions - we want pull requests and to
hear about issues.

[NoPorts](https://docs.noports.com) on Juniper
[Junos OS Evolved](https://www.juniper.net/documentation/us/en/software/junos/overview-evo/index.html):
the stock `sshnpd` daemon packaged as a third-party Docker container running
on the routing engine — giving operators SSH (plus, via `npt`,
NETCONF/gRPC) access to the router with **no inbound listening ports** on
the management plane.

> **Scope: Junos OS Evolved only.** Junos OS Evolved is native Linux and
> officially supports third-party Docker containers (see
> [Platform notes](#platform-notes-junos-os-evolved-container-support));
> we recommend 22.4R1 or later. **Classic Junos OS cannot run sshnpd**: it
> is FreeBSD-based and Dart (which sshnpd is written in) has no FreeBSD
> target. Classic boxes are still reachable through NoPorts via a
> [jump device](#classic-junos-os-the-jump-device-pattern).

**New here? Start with the [Quickstart](QUICKSTART.md)** — tarball to
SSH session, step by step.

## Who is this for?

### Network operators

Grab `noports-junos-evolved.tar` from the
[releases page](https://github.com/atsign-foundation/noports-junos-evolved/releases),
sideload it onto the routing engine, onboard with a one-time passcode. You
will need NoPorts atSigns for your devices; start at
[noports.com](https://noports.com).

### Contributors

[CONTRIBUTING.md](CONTRIBUTING.md) has the general guidance. The image
builds and smoke-tests anywhere Docker runs; full on-device testing uses
the freely downloadable vJunos-Evolved image — see
[Development](#development).

## How it works

The deliverable is a single Docker image (Ubuntu 22.04 base, the family
Juniper qualifies) bundling the stock NoPorts release binaries. On the
router it runs from the dedicated `/var/extensions` partition, shares the
host network namespace so it can reach both the management network
(outbound, to the atProtocol servers) and the local Junos `ssh` service on
port 22 (inbound sessions), and keeps its APKAM keys on a bind-mounted host
directory so they survive container restarts and image upgrades.

| Piece | Path | Purpose |
|---|---|---|
| `sshnpd` | `/usr/local/bin/sshnpd` (in image) | Stock NoPorts release binary (x86_64) |
| `at_activate` | `/usr/local/bin/at_activate` (in image) | APKAM enrollment (cuts keys on the router) |
| [`entrypoint.sh`](docker/entrypoint.sh) | `/usr/local/bin/entrypoint.sh` (in image) | Validates env config, waits for onboarding, execs sshnpd |
| [`onboard-noports.sh`](docker/onboard-noports.sh) | `/usr/local/bin/onboard-noports.sh` (in image) | One-time APKAM device enrollment (`docker exec`) |
| Config env file | `/var/extensions/noports/noports.env` (on RE) | `DEVICE_ATSIGN`, `MANAGER_ATSIGN`, `DEVICE_NAME`, … (see [noports.env.example](noports.env.example)) |
| APKAM atKeys | `/var/extensions/noports/keys/` (on RE) | Device identity, created by enrollment, bind-mounted into the container |

The pinned sshnpd release lives in [SSHNPD_VERSION](SSHNPD_VERSION) and is
bumped automatically by CI when NoPorts publishes a new release, with
[schema-drift detection](upstream/README.md) against the upstream config
surface.

## Platform notes: Junos OS Evolved container support

Everything below is from Juniper's documentation —
[Running Third-Party Applications in Containers](https://www.juniper.net/documentation/us/en/software/junos/overview-evo/topics/topic-map/third-party-applications-deploying.html)
and
[Overview of Third-Party Applications on Junos OS Evolved](https://www.juniper.net/documentation/us/en/software/junos/overview-evo/topics/topic-map/third-party-applications-junos-os-evolved.html):

- Junos OS Evolved supports third-party Docker containers (release 20.1R1
  and later); containers are managed with the standard Docker Linux
  workflow from the shell.
- Containers are installed in a **separate partition mounted at
  `/var/extensions`** and persist across reboots and software upgrades.
  Size is platform driven: 8 GB or 30% of `/var`, whichever is smaller.
- **Ubuntu-based images are the only containers officially qualified by
  Juniper** — this image uses `ubuntu:22.04`.
- **Containers and files inside containers do not need to be signed**
  (Junos OS Evolved's IMA integrity enforcement applies to native
  applications, not container contents).
- Default resource limits for all containers combined: **2 GB memory, 20%
  of one CPU core** — plenty for sshnpd, and tunable via
  `/etc/extensions/platform_attributes`.
- The Docker service is not running by default:
  `systemctl enable --now docker.service` from the shell.
- Junos OS Evolved high availability features do not apply to custom
  containers; use `--restart unless-stopped` so Docker restarts the
  container after reboots (once the docker service is enabled).

### Networking and the management VRF

sshnpd needs (a) outbound internet via the management interface and (b) to
reach the local Junos `ssh` service (port 22). This image is designed to
run with `--network host`, sharing the routing engine's network namespace.

Per
[Juniper's container docs](https://www.juniper.net/documentation/us/en/software/junos/overview-evo/topics/topic-map/third-party-applications-deploying.html)
and
[Management Interface in a Dedicated Instance](https://www.juniper.net/documentation/us/en/software/junos/junos-getting-started-evo/junos-getting-started/topics/topic-map/management-interface-in-non-default-instance.html):

- If you have **not** configured `set system management-instance`,
  management traffic uses the default instance and host networking works
  as-is.
- If the management interface is in the dedicated **`mgmt_junos` VRF**
  (`set system management-instance`), the container's traffic must be bound
  to that VRF:
  - **Releases up to 23.4R1**: containers inherit the VRF of the Docker
    daemon; Junos OS Evolved ships a `docker@vrf.service` template unit to
    start a Docker daemon instance in a given VRF (default `vrf0`) —
    e.g. `systemctl enable --now docker@mgmt_junos` and use
    `docker -H unix:///run/docker-mgmt_junos.sock …`
    *(TODO-verify: the exact instance name and socket path for the
    `mgmt_junos` VRF on real hardware — not yet validated by us).*
  - **Releases 24.1R1 and later**: start the container with `--privileged`
    sharing the host network namespace and bind it to the VRF with
    `ip vrf exec mgmt_junos …`; pass `--dns ::1` to `docker run` for DNS
    resolution in the host network namespace
    *(TODO-verify: end-to-end on 24.x hardware).*
- DNS inside the container follows the Docker daemon/host configuration —
  if name resolution fails, check `/etc/resolv.conf` on the RE and see the
  [Quickstart troubleshooting table](QUICKSTART.md#troubleshooting).

## Installation (short version)

The [Quickstart](QUICKSTART.md) has the full copy-paste walkthrough.

```text
# from your machine
scp build/noports-junos-evolved.tar admin@<router>:/var/tmp/

# on the router
admin@router> start shell
$ su -                                    # container management needs root
# systemctl enable --now docker.service   # first time only
# docker load < /var/tmp/noports-junos-evolved.tar
# mkdir -p /var/extensions/noports/keys
# vi /var/extensions/noports/noports.env  # see noports.env.example
# docker run -d --name noports --restart unless-stopped --network host \
    --env-file /var/extensions/noports/noports.env \
    -v /var/extensions/noports/keys:/atsign/keys \
    noports-junos-evolved:latest
```

### Onboard the device with APKAM (no atKeys files copied around)

Enrollment cuts new, scope-limited APKAM keys **on the router**; the full
atKeys file for the device atSign never leaves the administrator's custody.

On the admin machine (any host with an authorized key for `@mydevice`):

```bash
at_activate otp -a @mydevice
```

On the router shell:

```bash
docker exec -it noports onboard-noports.sh <passcode>
```

While it waits, approve from the admin machine:

```bash
at_activate approve -a @mydevice --arx noports --drx junos_router_1
```

The entrypoint detects the new keys within ~30 seconds and starts sshnpd —
`docker logs noports` shows the daemon starting.

### Connect from anywhere

```bash
sshnp -f @manager -t @mydevice -d junos_router_1 -u <junos-user>
# or tunnel NETCONF (port 830) without SSH — requires
# PERMIT_OPEN=localhost:22,localhost:830 in noports.env and
# `set system services netconf ssh` on the router:
npt -f @manager -t @mydevice -d junos_router_1 -r localhost -p 830 -l 8300
ssh -p 8300 <junos-user>@localhost -s netconf
```

## Restricted egress (management-plane ACLs)

By default the atProtocol dials the atDirectory on `root.atsign.org:64`
and atServers on assorted high ports — typically blocked by management VRF
ACLs. The `proxy:` root-server form skips the directory lookup and sends
**all** atProtocol traffic to one reverse proxy on one port. In
`/var/extensions/noports/noports.env`:

```text
ROOT_SERVER=proxy:proxy0001.atsign.org:443
```

Both the daemon and APKAM enrollment honor it (set it **before**
onboarding, so enrollment traffic uses it too). Clients use the equivalent
flag, picking a relay with `-r`:

```bash
sshnp -f @manager -r @rv_oc -t @mydevice -d junos_router_1 \
  --root-domain "proxy:proxy0001.atsign.org:443"
```

Note: the proxy covers atProtocol (control-plane) traffic. The session data
path is a separate outbound connection from the router to the relay chosen
by the client (`-r`), so a 443-only egress policy also needs a relay
reachable on 443.

## Fleet-scale access control: policy atSigns

Listing manager atSigns per router works for a handful of devices, but at
fleet scale it means touching every router's env file to grant or revoke
an operator's access. A **policy atSign** centralizes that decision: the
daemon delegates each incoming request to a
[NoPorts Policy Service](https://docs.noports.com) running as that atSign,
which answers allow/deny based on centrally-managed rules.

```bash
# /var/extensions/noports/noports.env
DEVICE_ATSIGN=@mydevice
POLICY_ATSIGN=@policy_np
DEVICE_NAME=junos_router_1
```

At least one of `MANAGER_ATSIGN` / `POLICY_ATSIGN` must be set:

- **`POLICY_ATSIGN` only** — every request is decided by the policy
  service; the router's env file never changes as staff or entitlements
  change. The entrypoint also stops defaulting `PERMIT_OPEN` to
  `localhost:22` in this mode, so port restrictions defer to policy
  (`*:*`) unless you set `PERMIT_OPEN` explicitly.
- **both** — atSigns in `MANAGER_ATSIGN` get direct access (policy is not
  consulted for them); everyone else is checked against the policy
  service. Useful as a break-glass list alongside central control.

## Classic Junos OS: the jump-device pattern

Classic (FreeBSD-based) Junos OS cannot run sshnpd — Dart has no FreeBSD
compile target. To manage classic boxes with NoPorts, run sshnpd on a small
Linux host (or a Junos OS Evolved box) in the same management network with
`PERMIT_OPEN` entries for the classic devices, then point `npt`/`sshnp` at
those host:port pairs:

```text
# on the jump device: PERMIT_OPEN=localhost:22,192.0.2.10:22,192.0.2.10:830
npt -f @manager -t @jumpdevice -d mgmt_jump -r 192.0.2.10 -p 22 -l 2222
ssh -p 2222 admin@localhost         # SSH to the classic box, via the jump
```

## Development

```bash
make fetch    # stage pinned sshnpd + at_activate in build/
make image    # docker build --platform linux/amd64
make tar      # docker save > build/noports-junos-evolved.tar
make lint     # shellcheck + hadolint (via docker)
```

CI ([.github/workflows/ci.yaml](.github/workflows/ci.yaml)) lints, builds
the image, checks the [upstream config schema](upstream/README.md) for
drift, and runs a docker smoke test: the container starts with test env
vars, the entrypoint must reach the waiting-for-onboarding loop, and the
packaged binaries must execute.

**On-device CI is image-gated**: vJunos-Evolved is freely downloadable
from Juniper and runs under
[containerlab](https://containerlab.dev/manual/kinds/vr-vjunosevolved/)
(kind `juniper_vjunosevolved`), but the image must be built locally with
vrnetlab and cannot be redistributed, so it is not run in GitHub CI. The
documented lab topology is
[clab/vjunos-lab.clab.yml](clab/vjunos-lab.clab.yml).

## Roadmap

- **Done (this scaffold):** container packaging of the pinned sshnpd
  release, env-file configuration, persistent on-box APKAM keys, on-box
  enrollment, proxy-mode (443-only) egress support, CI lint/build/smoke
  with upstream schema-drift detection, automated sshnpd bumps.
- **Next: validation on vJunos-Evolved and hardware** — the Junos
  CLI/shell walkthrough below and in the Quickstart follows Juniper's
  documentation but has not yet been executed on a device; see the
  TODO-verify items in [Networking](#networking-and-the-management-vrf).
- **Later: native Junos configuration (Phase 2, experimental scaffold in
  [yang/](yang/noports.yang)).** Junos supports custom YANG packages —
  `request system yang add package noports module noports.yang
  action-script noports-action.py` — which merge new hierarchies into the
  CLI schema, with Python 3 action/translation scripts since Junos OS
  Evolved 22.3R1
  ([Juniper docs](https://www.juniper.net/documentation/us/en/software/junos/netconf/topics/task/netconf-yang-packages-managing.html)).
  The goal is SR Linux-style native config: `set noports device-atsign
  @mydevice` from the Junos CLI, with the action script rendering the env
  file and bouncing the container. **The files in `yang/` are unvalidated
  scaffolding** — they lint clean (`pyang --strict`, `py_compile`) but are
  not wired up and have never been loaded on a device.

## Maintainers

Created by Atsign. Original author:
[Colin Constable](https://github.com/cconstab) ([@colin](https://atsign.com)).
Issues and pull requests are welcome — they are triaged weekly.
