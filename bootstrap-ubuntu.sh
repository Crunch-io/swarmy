#!/bin/bash -ex

GIT_BRANCH=master
NEXT_SCRIPT=stage2.sh
HOSTNAME_ARGS="-2 --domain-tag=Domain --prefix-tag=aws:autoscaling:groupName"
PIP_ARGS=""

#Other ENV Args
DEBIAN_FRONTEND=noninteractive

#Update all local packages
apt-get update -q && apt-get upgrade -qy

#First set up a list of packages to install
PKGS="python-virtualenv curl"

apt-get install -qy $PKGS


#Create a virtualenv
virtualenv VENV
. VENV/bin/activate

mkdir -p swarmy
curl -sL https://github.com/Crunch-io/swarmy/tarball/master | tar -xz --strip-components=1 -C swarmy

cd swarmy
python setup.py develop $PIP_ARGS

if [ -f $NEXT_SCRIPT ]; then
    exec $NEXT_SCRIPT
fi
