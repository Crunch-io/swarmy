#!/bin/bash -xe

# This currently works only for systems on EC2. Other systems should be
# possible, but will require some work.
# It has not yet been tested on Ubuntu

# Assumptions (ENVVAR that overrides it):
# * We want all ephemeral devices mounted as RAID0 (RAIDLEVEL) on /scratch0 (MOUNTPOINT)
#   * Filesystem type is ext4 (FS_TYPE)
#   * mkfs options are no journaling, and no root reservation (FS_OPTIONS, TUNE2FS_OPTIONS)
#   * FS is labeled 'ephemeral-data' (FS_LABEL)
#   * Mount is set up in writeback mode, noatime nodiratime (MOUNT_OPTIONS)
#     these may not work for non-ext4
#   * No other setup is made (subdirs, etc)
# * We want ext4 (FS_TYPE)
#   * tune2fs is set up to run always, this may not be appropriate for xfs and other fs types

#TODO This should probably be a python script because of all the magic bashisms
#  that are difficult to interpret by humans
#     This needs safety precautions so that we don't accidentally wipe the boot
#  volume or other EBS volumes that are mounted

SWARMYDIR=${SWARMYDIR:-/root/.swarmy}
RAIDLEVEL=${RAIDLEVEL:-0}
RAIDNAME=${RAIDNAME:-data}
DEVICES=()

if [ -z "$SWARMYDIR" ]; then
    echo "SWARMYDIR is not set, this script should be run from swarmy. Cowardly refusing to continue."
    exit 1
fi

function get_metadata {
    curl -s http://169.254.169.254$1
}

function get_ephemeral_disks {
    itype=$1

	# This is a hard coded list. :'(
    case $itype in
      r3.8xlarge|c3.*|m3.xlarge|m3.2xlarge)
        DEVICES+=('xvdc');&
      r3.large|r3.xlarge|r3.2xlarge|r3.4xlarge|m3.medium|m3.large)
        DEVICES+=('xvdb')
        ;;
      i3.16xlarge)
        DEVICES+=('nvme4n1' 'nvme5n1' 'nvme6n1' 'nvme7n1');&
      i3.8xlarge)
        DEVICES+=('nvme2n1' 'nvme3n1');&
      i3.4xlarge)
        DEVICES+=('nvme1n1');&
      i3.large|i3.xlarge|i3.2xlarge)
        DEVICES+=('nvme0n1')
        ;;
    esac

}

#actually gets the av zone
REGION=$(get_metadata /latest/meta-data/placement/availability-zone/)
#remove the last char of the zone to get region
REGION=${REGION%?}
INSTANCE_ID=$(get_metadata /latest/meta-data/instance-id/)
INSTANCE_TYPE=$(get_metadata /latest/meta-data/instance-type/)

#Check to see what devices we need to mount
#Get the list of EBS volumes mapped to the system


get_ephemeral_disks $INSTANCE_TYPE

#length of the array
NUM_DEVICES=${#DEVICES[@]}
MDDEV=

if [ "$NUM_DEVICES" -eq 1 ]; then
    # If we only have a single device, we just move on
    MDDEV=/dev/${DEVICES}
    echo "We only found a single device. No further work necessary"
else
    MDDEV=/dev/md/${RAIDNAME}
    MDADM=$(command -v mdadm)
    BLOCKDEV=$(command -v blockdev)

    if [ -z "$MDADM" -o -z "$BLOCKDEV" ]; then
        echo "mdadm or blockdev tools not found. Cowardly exiting since we should be creating a md device."
        exit 1
    fi
    # Verify that we haven't already been run...

    # Look at mdadm.conf
    if grep -q $MDDEV /etc/mdadm.conf; then
        if [ ! -b $MDDEV ]; then
            # TODO Need to undo the mdadm.conf change because we're broken. This happens if we stop/start our instance
            echo "The device $MDDEV does not exist, but is is configured in mdadm.conf. Requires intervention to fix. Cowardly refusing to continue."
        else
            echo "The device $MDDEV is already configured in mdadm.conf. This script is a no-op."
        fi
    elif [ -b $MDDEV ]; then
        echo "The device $MDDEV already exists, but is not configured in mdadm.conf. Requires intervention to fix. Cowardly refusing to continue."
        exit 2
    else
        # fix ephemeral, where mounted on /mnt
        # WARNING, this wipes devices
        for dev in ${DEVICES[@]}; do
            if $(mount | grep -q "/dev/${dev}"); then
                umount -f /dev/${dev}
                dd if=/dev/zero of=/dev/$dev bs=10MB count=1
                # Remove any /mnt mounts, which would the most likely cause for
                # the above device to be mounted. Linux has so many ways to
                # mount a device there is no clean/clear way to find out what
                # /etc/fstab line refers to a device that is mounted
                sed -i -e "\#.*\s/mnt\s.*#d" /etc/fstab
            fi
        done

        # Do the work
        # Make the RAID$RAIDLEVEL device
        (
            cd /dev
            yes | $MDADM --create --force --verbose --level=$RAIDLEVEL $MDDEV --name=$RAIDNAME --raid-devices=$NUM_DEVICES ${DEVICES[@]}
            $MDADM --wait $MDDEV || true
            $MDADM --detail --scan >> /etc/mdadm.conf
            blockdev --setra 65536 $MDDEV
            echo $((30*1024)) > /proc/sys/dev/raid/speed_limit_min
        )
    fi
fi

if [ -n "$MDDEV" ]; then
    echo -n "$MDDEV" > $SWARMYDIR/ephemeraldev
fi
touch $SWARMYDIR/prepephemeral.run

