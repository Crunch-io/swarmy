#!/bin/bash -e

# This script is meant to be chainloaded after prepephemeral.sh as it will use
# the ephemeral device, create a filesystem on it and mount it on the the
# mountpoint.

# Assumptions (ENVVAR that overrides it):
#   * Filesystem type is ext4 (FS_TYPE)
#   * mkfs options are no journaling, and no root reservation (FS_OPTIONS, TUNE2FS_OPTIONS)
#   * FS is labeled 'ephemeral-data' (FS_LABEL)
#   * Mount is set up in writeback mode, noatime nodiratime (MOUNT_OPTIONS)
#     these may not work for non-ext4
#   * No other setup is made (subdirs, etc)
# * We want ext4 (FS_TYPE)
#   * tune2fs is set up to run always, this may not be appropriate for xfs and other fs types

MOUNTPOINT=${MOUNTPOINT:-/scratch0}
FS_TYPE=${FS_TYPE:-ext4}
FS_LABEL=${FS_LABEL:-ephemeral-data}
FS_OPTIONS=${FS_OPTIONS:-"-q -O ^has_journal"}
TUNE2FS_OPTIONS=${TUNE2FS_OPTIONS:-"-m 0"}

#if defined, precede with a comma
MOUNT_OPTIONS=${MOUNT_OPTIONS:-"defaults,data=writeback,noatime,nodiratime"}

if [ -z "$SWARMYDIR" ]; then
    echo "SWARMYDIR is not set, this script should be run from swarmy. Cowardly refusing to continue."
    exit 1
fi

if [ ! -f "$SWARMYDIR/ephemeraldev" ]; then
    echo "$SWARMYDIR/ephemeraldev does not exist, not sure where to format/mount"
    exit 1
fi

read DEVICE < $SWARMYDIR/ephemeraldev


function is_mounted() {
    thing=$1
    mount | grep -q "$thing"
    return $?
}

function is_formatted() {
    device=$1
    fstype=$2

    test "$(blkid -o value -s TYPE $device)" = "$fstype"
    return $?
}

#Precondition checks: Make sure we haven't been run
(
    #Check to make sure we don't already have stuff mounted
    if is_mounted "$DEVICE"; then
        error "The mount device $DEVICE is already mounted"
    fi

    # Look at mount point to make sure nothing's mounted
    if is_mounted "$MOUNTPOINT"; then
        error "The mount point $MOUNTPOINT is already in use"
    fi

    # Look at fstab
    if grep -q LABEL=$FS_LABEL /etc/fstab; then
        error "The mount point LABEL=$FS_LABEL is already listed in /etc/fstab"
    fi
)

if [ -n "$FORCE" ] || ! is_formatted $MDDEV $FS_TYPE; then
    mkfs.$FS_TYPE -L $FS_LABEL $FS_OPTIONS $MDDEV
    if [ -n "$TUNE2FS_OPTIONS" ]; then
        tune2fs $TUNE2FS_OPTIONS $MDDEV
    fi
fi

# mount via LABEL not device name, in case it changes
echo LABEL=$FS_LABEL $MOUNTPOINT $FS_TYPE defaults,nofail,noatime,discard 0 2 >> /etc/fstab

#Mount it
mount $MOUNTPOINT

#Assert that it's mounted
if ! is_mounted "$MOUNTPOINT"; then
    echo "The mount point $MOUNTPOINT did not come up, aborting"
    exit 1
fi

touch $SWARMYDIR/mountephemeral.run
