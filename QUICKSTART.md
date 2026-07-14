# Quickstart

Zero to an SSH session with no open ports, on a Juniper Junos OS Evolved
box (22.4R1+ recommended; classic FreeBSD Junos is **not** supported — see
the [jump-device pattern](README.md#classic-junos-os-the-jump-device-pattern)).

> **Honesty note:** the Junos CLI/shell steps below follow Juniper's
> [container documentation](https://www.juniper.net/documentation/us/en/software/junos/overview-evo/topics/topic-map/third-party-applications-deploying.html)
> but have not yet been validated on vJunos-Evolved or hardware by this
> project — please open an issue for anything that doesn't match your box.

## What you need first

- Two Atsigns: one for the router (e.g. `@mydevice`) and one for you as the
  manager (e.g. `@manager`) — get them at [noports.com](https://noports.com)
- The manager Atsign activated on your own machine, with the NoPorts client
  installed ([client install guide](https://docs.noports.com))
- The image tarball: download `noports-junos-evolved.tar` from the
  [releases page](https://github.com/atsign-foundation/noports-junos-evolved/releases),
  or build it yourself: `make fetch tar` (needs Docker)

## Step 1: copy the tarball to the router

```bash
scp build/noports-junos-evolved.tar admin@<router>:/var/tmp/
```

(or from the Junos CLI:
`file copy scp://you@host/path/noports-junos-evolved.tar /var/tmp/`)

## Step 2: load and run the container

Drop to the Linux shell — container management is plain Docker, as root:

```text
admin@router> start shell
$ su -
```

First time only: enable Docker (containers live in the dedicated
`/var/extensions` partition and survive reboots and upgrades):

```bash
systemctl enable --now docker.service
```

Load the image and prepare the config:

```bash
docker load < /var/tmp/noports-junos-evolved.tar
mkdir -p /var/extensions/noports/keys
vi /var/extensions/noports/noports.env
```

`noports.env` (see [noports.env.example](noports.env.example)):

```text
DEVICE_ATSIGN=@mydevice
MANAGER_ATSIGN=@manager
DEVICE_NAME=junos_router_1
# behind restrictive egress ACLs, set BEFORE onboarding:
# ROOT_SERVER=proxy:proxy0001.atsign.org:443
# to also tunnel NETCONF with npt:
# PERMIT_OPEN=localhost:22,localhost:830
```

Run it:

```bash
docker run -d --name noports \
  --restart unless-stopped \
  --network host \
  --env-file /var/extensions/noports/noports.env \
  -v /var/extensions/noports/keys:/atsign/keys \
  noports-junos-evolved:latest

docker logs -f noports    # expect: "waiting for atKeys ..."
```

> **Management VRF:** if the router uses
> `set system management-instance` (the `mgmt_junos` VRF), the container's
> traffic must be bound to that VRF — see
> [Networking and the management VRF](README.md#networking-and-the-management-vrf)
> for the release-dependent options (docker@vrf daemon instance on
> ≤23.4R1, `ip vrf exec` on 24.1R1+).

## Step 3: onboard the router with APKAM

Enrollment cuts scope-limited keys **on the router** — no atKeys file is
ever copied to it.

```bash
# on your machine: generate a one-time passcode for the device Atsign
at_activate otp -a @mydevice

# on the router shell:
docker exec -it noports onboard-noports.sh <passcode>

# back on your machine, while the router waits: approve the enrollment
at_activate approve -a @mydevice --arx noports --drx junos_router_1
```

The entrypoint detects the keys within ~30 seconds and starts sshnpd:

```bash
docker logs -f noports    # expect sshnpd startup, then "monitor started"
```

## Step 4: connect — from your machine, anywhere on the internet

```bash
sshnp -f @manager -t @mydevice -d junos_router_1 -u admin
```

Bonus — tunnel NETCONF without SSH (add `localhost:830` to `PERMIT_OPEN`
first, and `set system services netconf ssh` on the router):

```bash
npt -f @manager -t @mydevice -d junos_router_1 -r localhost -p 830 -l 8300
ssh -p 8300 admin@localhost -s netconf
```

### Management-plane ACLs block outbound?

Set proxy mode in `noports.env` **before** onboarding, so enrollment
traffic uses it too:

```text
ROOT_SERVER=proxy:proxy0001.atsign.org:443
```

then `docker restart noports`, and connect with the matching client flags:

```bash
sshnp -f @manager -r @rv_oc -t @mydevice -d junos_router_1 -u admin \
  --root-domain "proxy:proxy0001.atsign.org:443"
```

(The proxy covers control-plane traffic; the session data path goes to the
relay the client picks with `-r`, so 443-only egress also needs a relay on
443 — see the [README](README.md#restricted-egress-management-plane-acls).)

## Troubleshooting

| Symptom | Check |
|---|---|
| Container exits immediately | `docker logs noports` — the entrypoint names the missing env var (DEVICE_ATSIGN, MANAGER_ATSIGN, DEVICE_NAME). Fix `/var/extensions/noports/noports.env`, then `docker rm -f noports` and re-run. |
| Container not running after reboot | `docker ps -a`; confirm `systemctl is-enabled docker.service` and that the container was started with `--restart unless-stopped`. |
| Stuck at `waiting for atKeys` | Expected before enrollment — run the onboard step. If it persists after enrollment, check the keys landed: `ls /var/extensions/noports/keys/` (must match `<device-atsign>_key.atKeys`) and that the same dir is mounted at `/atsign/keys`. |
| sshnpd starts then keeps exiting | `docker logs noports`. Common causes: no egress from the mgmt network (try proxy mode), bad keys, clock skew (`show system uptime`). |
| No egress / mgmt VRF reachability | From the RE shell: `curl -v https://proxy0001.atsign.org` (prefix with `ip vrf exec mgmt_junos` when using the dedicated management instance). If that fails, it's ACLs/routing, not NoPorts. |
| DNS resolution fails in the container | Check `/etc/resolv.conf` on the RE; on 24.1R1+ with host networking Juniper documents passing `--dns ::1` to `docker run`. |
| Onboard script hangs then fails | Enrollment wasn't approved in time — check from your machine with `at_activate list -a @mydevice -s pending`, approve, and re-run. If it never reaches the atServer, test egress (row above) and use proxy mode. |
| Daemon runs but `sshnp` can't connect | Verify the client uses the same device name (`-d`), the manager Atsign is in `MANAGER_ATSIGN`, and (behind strict ACLs) that the relay chosen with `-r` is reachable outbound from the router. |
| `npt` to 830 refused | `set system services netconf ssh` committed? `localhost:830` in `PERMIT_OPEN`? (restart the container after changing the env file) |
| Re-enrolling a device | Delete the key file in `/var/extensions/noports/keys/`, revoke the old enrollment (`at_activate revoke` from your machine), and run the onboard step again. |
| Out of space loading the image | Containers live in the `/var/extensions` partition (8 GB or 30% of `/var`, whichever is smaller) — `df -h /var/extensions`, prune old images with `docker image prune`. |

Config changes: edit `/var/extensions/noports/noports.env`, then
`docker restart noports`.
