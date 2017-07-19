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

RAIDLEVEL=${RAIDLEVEL:-0}
RAIDNAME=${RAIDNAME:-data}
DEVICES=()

if [ -z "$SWARMYDIR" ]; then
    echo "SWARMYDIR is not set, this script should be run from swarmy. Cowardly refusing to continue."
    exit 1
fi

#Find aws somewhere
function find_aws {

    # If AWSCMD is not set, try to use command -v to find it, in $PATH
    if [ -z "$AWSCMD" ]; then
        AWSCMD=$(command -v aws)
    fi

    if [ -z "$AWSCMD" ]; then
        # This looks for aws cli in the VENV set up by swarmy, the VENV set up by
        # ansible, or the PATH (system package or pip install)
        for loc in /root/VENV/bin/aws /var/lib/crunch.io/venv/bin/aws; do
            if [ -x "$loc" ]; then
                echo $loc
                return 0
            fi
        done
        echo "No aws cli found in the common locations: cowardly refusing to continue"
        exit 1
    else
        echo "aws command found: $AWSCMD"
    fi
}

find_aws

function get_metadata {
    curl -s http://169.254.169.254$1
}

#actually gets the av zone
REGION=$(get_metadata /latest/meta-data/placement/availability-zone/)
#remove the last char of the zone to get region
REGION=${REGION%?}
INSTANCE_ID=$(get_metadata /latest/meta-data/instance-id/)

#Check to see what devices we need to mount
#Get the list of EBS volumes mapped to the system
EBS_VOLUMES=$($AWSCMD ec2 --region $REGION describe-instances --instance-ids $INSTANCE_ID  --query "Reservations[0].Instances[0].BlockDeviceMappings[*].DeviceName" --output text | sed -e 's#^/dev/sd\([a-z]\)[0-9]\+$#xvd\1#')

#Get the list of block devices by name
ALL_BLK_DEVICES=$(lsblk -ln -o NAME)
for dev in $ALL_BLK_DEVICES; do
    # NOTE: we assume that you won't have both on one system
    case $dev in
      nvme*)
        DEVICES+=($dev)
        ;;
      xvd?)
        #Make sure these are ephemeral, not EBS volumes
        if ! [[ "$EBS_VOLUMES" =~ $dev[:digit:]? ]]; then
            DEVICES+=($dev)
        fi
        ;;
    esac
done

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
        echo "The device $MDDEV is already configured in mdadm.conf. This script is a no-op."
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
            $MDADM --create --force --verbose --level=$RAIDLEVEL $MDDEV --name=$RAIDNAME --raid-devices=$NUM_DEVICES ${DEVICES[@]}
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

