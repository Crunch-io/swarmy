#!/bin/bash

if [ -n "$DEBUG" ]; then
    set -x
fi

# First, let's deal with the hostname:
dynamic_hostname $HOSTNAME_ARGS

### TODO: do this, or write a util.py
#if [ -n "$JENKINS_BASE" ]; then
#    # Now, let's curl out to jenkins to run the deploy
#    CURL_ARGS="-s"
#    if [ -n "$JENKINS_USER" ]; then
#        CURL_ARGS="$CURL_ARGS --user $JENKINS_USER"
#    fi
#    curl $CURL_ARGS $JENKINS_BASE
#fi
if [ -n "$DEBUG" ]; then
    # This helps us to know that this was run completely
    touch /root/stage-2.run
fi
