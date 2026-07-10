# NoPorts sshnpd for Juniper Junos OS Evolved third-party container support.
#
# Ubuntu base: "Ubuntu based Docker containers ... are the only containers
# that are officially qualified by Juniper Networks" —
# https://www.juniper.net/documentation/us/en/software/junos/overview-evo/topics/topic-map/third-party-applications-deploying.html
# 22.04 LTS is chosen (over 24.04) for the widest kernel compatibility with
# in-service Junos OS Evolved releases; containers and the files inside them
# do NOT need IMA signing (only native apps do).
#
# Build from the repo root (see Makefile):
#   ./scripts/fetch-sshnpd.sh
#   docker build --platform linux/amd64 -f docker/Dockerfile -t noports-junos-evolved .
FROM ubuntu:22.04

# openssh-client: sshnpd's default ssh-client is openssh (ssh + ssh-keygen)
# ca-certificates: outbound TLS to the atDirectory / atServers / relays
# DL3008: apt version pins are brittle across Ubuntu point releases; the
# base image tag pins the package universe well enough for this image.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Stock NoPorts release binaries, staged by scripts/fetch-sshnpd.sh
# (pinned version: see SSHNPD_VERSION at the repo root)
COPY build/sshnpd build/at_activate /usr/local/bin/

COPY docker/entrypoint.sh docker/onboard-noports.sh /usr/local/bin/

# APKAM atKeys live on a bind-mounted host dir (/var/extensions/noports/keys
# on the routing engine) so they survive container restarts and upgrades.
ENV NOPORTS_KEYS_DIR=/atsign/keys \
    HOME=/atsign
VOLUME /atsign/keys

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
