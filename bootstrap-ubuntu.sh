#!/bin/bash -ex

#Settings needed to bootstrap and load settings
GIT_BRANCH=${GIT_BRANCH:-master}
PIP_ARGS=""
SETTINGS_URL=""

# Can be set here, or loaded from s3 settings
NEXT_SCRIPT=${NEXT_SCRIPT:-scripts/stage2.sh}
DEBUG=true

#Other ENV Args useful for pre-tasks
DEBIAN_FRONTEND=noninteractive

#Update all local packages
apt-get update -q && apt-get upgrade -qy

#First set up a list of packages to install
PKGS="python-virtualenv curl"

apt-get install -qy $PKGS

#Create a virtualenv
virtualenv VENV
. VENV/bin/activate

if [ ! -d swarmy ]
then
    mkdir -p swarmy
    curl -sL https://github.com/Crunch-io/swarmy/tarball/master | tar -xz --strip-components=1 -C swarmy
fi

cd swarmy
python setup.py develop $PIP_ARGS

function download_next
{
    # Usage: FILE=$(download_next URL [tmpfile_suffix])
    # FILE will be set to the local path of the file
    # Calling method is responsible for deleting the file

    OUT=$(mktemp --suffix="$2" bootstrap_ubuntu.XXXXXXXXXX) || { echo "Failed to create temp file"; exit 1; }
    case "$1" in
      s3://*)
        #Download the script, set perms, and then execute
        # AWSCLI is a req of swarmy and is installed during setup.py develop above
        aws s3 cp $1 $OUT
        ;;
      http*://*)
        #Download the script using curl, then execute
        curl -sL $1 > $OUT
        ;;
      *)
        cat $1 > $OUT
        ;;
    esac

    echo -n $OUT
}

# Load environment settings from URL
SETTINGS_URL=${SETTINGS_URL:-s3://crunchio-autoscale/.profile}

SSS=$(download_next $SETTINGS_URL .profile)

set +e

source $SSS

#clean up
if [ -z "$DEBUG" ]; then
    rm -f $SSS
fi
set -e

# Call the next script
if [ -f $NEXT_SCRIPT ]; then
    SCRIPT=$(download_next $NEXT_SCRIPT .stage2.sh)
    chmod a+x $SCRIPT

    $SCRIPT

    if [ -z "$DEBUG" ]; then
        rm -f $SCRIPT
    fi
else
    if [ -n "$DEBUG" ]; then
        echo "No stage 2 provided."
    fi
fi

