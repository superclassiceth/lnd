#!/bin/bash

# Simple bash script to build basic lnd tools for all the platforms
# we support with the golang cross-compiler.
#
# Copyright (c) 2016 Company 0, LLC.
# Use of this source code is governed by the ISC
# license.

set -e

# If no tag specified, use date + version otherwise use tag.
if [[ $1x = x ]]; then
    DATE=`date +%Y%m%d`
    VERSION="01"
    TAG=$DATE-$VERSION
else
    TAG=$1

    # If a tag is specified, ensure that that tag is present and checked out.
    if [[ $TAG != $(git describe) ]]; then
        echo "tag $TAG not checked out"
        exit 1
    fi

    # Build lnd to extract version.
    go build github.com/lightningnetwork/lnd/cmd/lnd

    # Extract version command output.
    LND_VERSION_OUTPUT=`./lnd --version`

    # Use a regex to isolate the version string.
    LND_VERSION_REGEX="lnd version (.+) commit"
    if [[ $LND_VERSION_OUTPUT =~ $LND_VERSION_REGEX ]]; then
        # Prepend 'v' to match git tag naming scheme.
        LND_VERSION="v${BASH_REMATCH[1]}"
        echo "version: $LND_VERSION"

        # If tag contains a release candidate suffix, append this suffix to the
        # lnd reported version before we compare.
        RC_REGEX="-rc[0-9]+$"
        if [[ $TAG =~ $RC_REGEX ]]; then 
            LND_VERSION+=${BASH_REMATCH[0]}
        fi

        # Match git tag with lnd version.
        if [[ $TAG != $LND_VERSION ]]; then
            echo "lnd version $LND_VERSION does not match tag $TAG"
            exit 1
        fi
    else
        echo "malformed lnd version output"
        exit 1
    fi
fi

go mod vendor
tar -cvzf vendor.tar.gz vendor

PACKAGE=lnd
MAINDIR=$PACKAGE-$TAG
mkdir -p $MAINDIR

cp vendor.tar.gz $MAINDIR/
rm vendor.tar.gz
rm -r vendor

PACKAGESRC="$MAINDIR/$PACKAGE-source-$TAG.tar"
git archive -o $PACKAGESRC HEAD
gzip -f $PACKAGESRC > "$PACKAGESRC.gz"

cd $MAINDIR

# If LNDBUILDSYS is set the default list is ignored. Useful to release
# for a subset of systems/architectures.
SYS=${LNDBUILDSYS:-"
        darwin-386
        darwin-amd64
        dragonfly-amd64
        freebsd-386
        freebsd-amd64
        freebsd-arm
        illumos-amd64
        linux-386
        linux-amd64
        linux-armv6
        linux-armv7
        linux-arm64
        linux-ppc64
        linux-ppc64le
        linux-mips
        linux-mipsle
        linux-mips64
        linux-mips64le
        linux-s390x
        netbsd-386
        netbsd-amd64
        netbsd-arm
        netbsd-arm64
        openbsd-386
        openbsd-amd64
        openbsd-arm
        openbsd-arm64
        solaris-amd64
        windows-386
        windows-amd64
        windows-arm
"}

# Use the first element of $GOPATH in the case where GOPATH is a list
# (something that is totally allowed).
PKG="github.com/lightningnetwork/lnd"
COMMIT=$(git describe --abbrev=40 --dirty)
COMMITFLAGS="-X $PKG/build.Commit=$COMMIT"

for i in $SYS; do
    OS=$(echo $i | cut -f1 -d-)
    ARCH=$(echo $i | cut -f2 -d-)
    ARM=

    if [[ $ARCH = "armv6" ]]; then
      ARCH=arm
      ARM=6
    elif [[ $ARCH = "armv7" ]]; then
      ARCH=arm
      ARM=7
    fi

    mkdir $PACKAGE-$i-$TAG
    cd $PACKAGE-$i-$TAG

    echo "Building:" $OS $ARCH $ARM
    env CGO_ENABLED=0 GOOS=$OS GOARCH=$ARCH GOARM=$ARM go build -v -trimpath -ldflags="-s -w -buildid= $COMMITFLAGS" -tags="autopilotrpc signrpc walletrpc chainrpc invoicesrpc watchtowerrpc" github.com/lightningnetwork/lnd/cmd/lnd
    env CGO_ENABLED=0 GOOS=$OS GOARCH=$ARCH GOARM=$ARM go build -v -trimpath -ldflags="-s -w -buildid= $COMMITFLAGS" -tags="autopilotrpc invoicesrpc walletrpc watchtowerrpc" github.com/lightningnetwork/lnd/cmd/lncli
    cd ..

    if [[ $OS = "windows" ]]; then
	zip -r $PACKAGE-$i-$TAG.zip $PACKAGE-$i-$TAG
    else
	tar -cvzf $PACKAGE-$i-$TAG.tar.gz $PACKAGE-$i-$TAG
    fi

    rm -r $PACKAGE-$i-$TAG
done

shasum -a 256 * > manifest-$TAG.txt
