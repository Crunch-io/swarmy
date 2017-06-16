#!/bin/bash

# The output from this script is found in the instance
# system log available through the AWS API, or the
# console.

#Settings needed to bootstrap and load settings
GIT_BRANCH=${GIT_BRANCH:-master}
#PIP_ARGS=""
# Can read multiple settings URLS by separating them with a space
#SETTINGS_URL=""
#DEBUG=true

# Can be set here, or loaded from s3 settings
#   Takes a semicolon separated list of scripts to run
NEXT_SCRIPT=${NEXT_SCRIPT:-""}


set -e
cd /root

# Directory where we store intermediate steps/arguments/things we want to share
# between scripts
if [ ! -d /root/.swarmy ]; then
    mkdir /root/.swarmy/
fi

export SWARMYDIR=/root/.swarmy/

if [ -z "$DEBUG" ]; then
    # If we aren't debugging, we just want to have stdout/stderr be redirect to
    # files instead so that we can check after the fact that things ran
    # successfully

    # Close STDOUT file descriptor
    exec 1<&-
    # Close STDERR FD
    exec 2<&-

    # Open STDOUT as $LOG_FILE file for read and write.
    exec 1<>$SWARMYDIR/log.stdout

    # Redirect STDERR to STDOUT
    exec 2<>$SWARMYDIR/log.stderr
else
    echo "Debug run of swarmy bootstrap.sh"
    set -x
    #printenv
fi

echo -n "Starting swarmy bootstrap: "
date

#Create a virtualenv, don't download new pip/setuptools
virtualenv --no-download VENV
. VENV/bin/activate

# This allows pinning pip/setuptools from your own PyPI repo
pip install $PIP_ARGS -U pip
pip install $PIP_ARGS -U setuptools

if [ ! -d swarmy ]
then
    mkdir -p swarmy
    # Do this in multiple steps so that a failure to download doesn't cause tar
    # to uncompress partially
    curl -sL -o swarmy.tar.gz \
        "https://api.github.com/repos/Crunch-io/swarmy/tarball/${GIT_BRANCH}"
    if [ $? -gt 0 ]; then
        echo "Failed to download Swarmy. Refusing to continue."
        rm -f swarmy.tar.gz
        exit 1
    fi
    tar -xzf swarmy.tar.gz --strip-components=1 -C swarmy
    rm -f swarmy.tar.gz
fi

pip install $PIP_ARGS -e swarmy

function download_next
{
    # Usage: FILE=$(download_next URL [tmpfile_suffix])
    # FILE will be set to the local path of the file
    # Calling method is responsible for deleting the file

    OUT=$(mktemp --suffix="$2" bootstrap.XXXXXXXXXX) || { echo "Failed to create temp file"; exit 1; }
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
    URLLIST=($SETTINGS_URL)
    for settings in ${URLLIST[@]}; do
        if [ -n "$settings" ]; then
            SSS=$(download_next $settings .profile)

            set +e

            source $SSS

            #clean up
            if [ -z "$DEBUG" ]; then
                rm -f $SSS
            fi
            set -e
        fi
    done
else
    if [ -n "$DEBUG" ]; then
        echo "No settings url provided."
    fi
fi

# Call the next script
# Make this an array
if [ -n "$NEXT_SCRIPT" ]; then
    read -a URLLIST <<<$NEXT_SCRIPT
    for script in ${URLLIST[@]}; do
        if [ -n "$script" ]; then
            SCRIPT=$(download_next $script .stage2.sh)
            
            source $SCRIPT

            if [ -z "$DEBUG" ]; then
                rm -f $SCRIPT
            fi
        fi
    done
else
    echo "No stage 2 provided."
fi

echo -n "Swarmy bootstrap script finished: "
date
