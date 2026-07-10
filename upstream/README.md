# Upstream schema snapshots

`sshnpd.yaml.example` is the example config file shipped inside the pinned
NoPorts release tarball (`config/sshnpd.yaml`), committed here as a
**schema snapshot**.

CI diffs the snapshot against the copy in the freshly fetched tarball on
every run. When NoPorts changes its config file schema (new, renamed or
removed keys), the weekly sshnpd bump PR turns **red with the exact diff**
— that is the signal to:

1. Review the schema change in the diff
2. Update the container entrypoint ([docker/entrypoint.sh](../docker/entrypoint.sh)),
   the env file example ([noports.env.example](../noports.env.example)) and —
   once wired up — the Phase 2 YANG model/action script
   ([yang/](../yang/noports.yang)) to match
3. Refresh the snapshot: `cp build/sshnp/config/sshnpd.yaml upstream/sshnpd.yaml.example`

This catches the dangerous case runtime checks cannot: a **renamed** key or
flag, where sshnpd would silently ignore our value and fall back to its
default.

Routers are never exposed to drift: the container image bundles the
entrypoint and sshnpd from the same pinned release, so the pair on any
device is always the combination CI tested.
