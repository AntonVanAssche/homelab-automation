#!/usr/bin/env bash

set -o errexit  # Abort on nonzero exit code.
set -o noglob   # Disable globbing.
set +o xtrace   # Disable debug mode.
set -o pipefail # Don't hide errors within pipes.

readonly NAME='rockpi-sata'
readonly VERSION='0.14'

# Prepare the tarball.
mkdir -p "${NAME}-${VERSION}"
mkdir -p "${NAME}-${VERSION}/usr/bin/"
mkdir -p "${NAME}-${VERSION}/etc/"
mkdir -p "${NAME}-${VERSION}/lib/systemd/system/"

cp -r "usr/bin/${NAME}/" "${NAME}-${VERSION}/usr/bin/"
cp -r "etc/${NAME}.conf" "${NAME}-${VERSION}/etc/"
cp -r "lib/systemd/system/${NAME}.service" "${NAME}-${VERSION}/lib/systemd/system/"

tar -czf "${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"

# Prepare the RPM build environment.
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy the tarball to the SOURCES directory.
cp -r "${NAME}-${VERSION}.tar.gz" ~/rpmbuild/SOURCES

# Copy the spec file to the SPECS directory.
cp -r "${NAME}.spec" ~/rpmbuild/SPECS

# Build the RPMs.
rpmbuild -bb ~/rpmbuild/SPECS/"${NAME}.spec"
