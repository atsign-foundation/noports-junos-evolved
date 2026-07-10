.PHONY: fetch image tar lint clean

# Image version; the release workflow overrides this from the git tag.
VERSION ?= 0.0.0-dev
IMAGE ?= noports-junos-evolved

# Download the pinned sshnpd release binaries (see SSHNPD_VERSION) into build/
fetch:
	./scripts/fetch-sshnpd.sh

# Build the container image for the Junos OS Evolved routing engine (x86_64)
image: build/sshnpd
	docker build --platform linux/amd64 -f docker/Dockerfile \
		-t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

# Save the image as a tarball for sideloading to /var/extensions on the box
tar: image
	docker save $(IMAGE):latest > build/noports-junos-evolved.tar
	@echo "Wrote build/noports-junos-evolved.tar"

build/sshnpd:
	./scripts/fetch-sshnpd.sh

# Lint shell scripts and the Dockerfile via Docker (no local installs)
lint:
	docker run --rm -v $(CURDIR):/mnt -w /mnt koalaman/shellcheck:stable \
		docker/entrypoint.sh docker/onboard-noports.sh scripts/fetch-sshnpd.sh
	docker run --rm -i hadolint/hadolint < docker/Dockerfile

clean:
	rm -rf build
