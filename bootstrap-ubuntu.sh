#!/bin/bash

# The output from this script is found in the instance
# system log available through the AWS API, or the
# console.

set -e
cd /root

#Settings needed to bootstrap and load settings
#TODO: GIT_BRANCH=${GIT_BRANCH:-master}
#PIP_ARGS=""
#SETTINGS_URL=""
#DEBUG=true

# Can be set here, or loaded from s3 settings
NEXT_SCRIPT=${NEXT_SCRIPT:-""}

if [ -n "$DEBUG" ]; then
    set -x
    #printenv
fi

#Other ENV Args useful for pre-tasks
DEBIAN_FRONTEND=noninteractive

#Update all local packages
apt-get -q update && apt-get -q upgrade -y

#First set up a list of packages to install
PKGS="python-virtualenv curl libyaml-dev python-dev"

apt-get -q install -y $PKGS

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
cd /root

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
        aws s3 cp --quiet $1 $OUT > /dev/null 2>&1
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
if [ -n "$SETTINGS_URL" ]; then
    SSS=$(download_next $SETTINGS_URL .profile)

    set +e

    source $SSS

    #clean up
    if [ -z "$DEBUG" ]; then
        rm -f $SSS
    fi
    set -e
else
    if [ -n "$DEBUG" ]; then
        echo "No settings file provided."
    fi
fi

# Call the next script
if [ -n "$NEXT_SCRIPT" ]; then
    SCRIPT=$(download_next $NEXT_SCRIPT .stage2.sh)

    source $SCRIPT

    if [ -z "$DEBUG" ]; then
        rm -f $SCRIPT
    fi
else
    if [ -n "$DEBUG" ]; then
        echo "No stage 2 provided."
    fi
fi

echo "Bootstrap script finished" >> /root/cloud-init-bootstrap.log
