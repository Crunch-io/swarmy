#!/bin/bash

GIT_BRANCH=master
NEXT_SCRIPT=stage2.sh
HOSTNAME_ARGS="-2 --domain-tag=Domain --prefix-tag=aws:autoscaling:groupName"
PIP_ARGS=""

#Update all local packages
apt-get update -q && apt-get upgrade -q

#First set up a list of packages to install
PKGS="python-virtualenv unzip curl"

apt-get install -q $PKGS


#Create a virtualenv
virtualenv VENV
. VENV/bin/activate

curl -sL https://github.com/Crunch-io/swarmy/tarball/master | tar -xz

cd swarmy
python setup.py develop $PIP_ARGS

exec $NEXT_SCRIPT
