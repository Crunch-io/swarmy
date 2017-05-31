#!/bin/bash -e

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
RAIDNAME=${RAIDNAME:-DATA}
MOUNTPOINT=${MOUNTPOINT:-/scratch0}
DEVICES=()
NUM_DEVICES=
FS_TYPE=${FS_TYPE:-ext4}
FS_LABEL=${FS_LABEL:-ephemeral-data}
FS_OPTIONS=${FS_OPTIONS:-"-q -O ^has_journal"}
TUNE2FS_OPTIONS=${TUNE2FS_OPTIONS:-"-m 0"}
#if defined, precede with a comma
MOUNT_OPTIONS=${MOUNT_OPTIONS:-"defaults,data=writeback,noatime,nodiratime"}

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

function error {
    echo $1
    exit 1
}

#Find aws somewhere
function find_aws {
    if [ -z $AWSCMD ]; then
        # This looks for aws cli in the VENV set up by swarmy, the VENV set up by
        # ansible, or the PATH (system package or pip install)
        for loc in /root/VENV/bin/aws /var/lib/crunch.io/venv/bin/aws $(which aws 2>/dev/null); do
            if [ -x "$loc" ]; then
                echo $loc
                return 0
            fi
        done
        error "No aws cli found in the common locations: aborting"
    else
        echo $AWSCMD
    fi
}

AWSCMD=$(find_aws)

function get_metadata {
    curl -s http://169.254.169.254$1
}

# Check the "all done successfully" idempotent run
#Assert that the $FS_LABEL exists, and is mounted
LABELDEV=$(blkid -o value -s NAME -L $FS_LABEL || true)
if [ -z "$FORCE" -a $? -eq 0 ] && is_mounted "$LABELDEV on $MOUNTPOINT"; then
    exit 0
fi

if [ ! -d $MOUNTPOINT ]; then
    mkdir -p $MOUNTPOINT
fi


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

if [ "$NUM_DEVICES" -eq 1 ]; then
    MDDEV=/dev/${DEVICES}
else
    MDDEV=/dev/md0
fi

# Undo/Force
if [ -n "$FORCE" ]; then
    # Unmount
    if is_mounted $MOUNTPOINT; then
        umount -f $MOUNTPOINT
    fi

    # Remove the fstab line
    sed -i -e "\#.*\s$MOUNTPOINT\s.*#d" /etc/fstab

    if [ "$NUM_DEVICES" -gt 1 ]; then
        (
        # Remove the mdadm.conf line
        sed -i -e "\#.*\s$MDDEV\s.*#d" /etc/mdadm.conf || true

        # Remove the Software Raid device
        mdadm --stop $MDDEV || true
        # Delete the device
        mdadm --remove $MDDEV || true
        # Remove them wiping their superblock
        cd /dev
        mdadm --zero-superblock ${DEVICES[@]} || true
        )
    fi
fi

#Precondition checks: Make sure we haven't been run
(
    #Check to make sure we don't already have stuff mounted
    if is_mounted "$MDDEV"; then
        error "The mount device $MDDEV is already mounted"
    fi

    # Look at mount point to make sure nothing's mounted
    if is_mounted "$MOUNTPOINT"; then
        error "The mount point $MOUNTPOINT is already in use"
    fi

    # Look at fstab
    if grep -q LABEL=$FS_LABEL /etc/fstab; then
        error "The mount point LABEL=$FS_LABEL is already listed in /etc/fstab"
    fi

    # Look at mdadm.conf
    if grep -q $MDDEV /etc/mdadm.conf; then
        error "The mount device $MDDEV is already configured in /etc/mdadm.conf"
    fi

    #fix ephemeral, where mounted on /mnt
    if is_mounted "/mnt"; then
        umount -f /mnt
        sed -i -e "\#.*\s/mnt\s.*#d" /etc/fstab
        #WARNING, this wipes devices
        for dev in ${DEVICES[@]}; do
            dd if=/dev/zero of=/dev/$dev bs=10MB count=1
        done
    fi
)

if [ $NUM_DEVICES -gt 1 ]; then
    if [ ! -f /usr/sbin/mdadm ]; then
        error "mdadm tools not found"
    fi
# Do the work
    #Make the RAID$RAIDLEVEL device
    (
        cd /dev
        mdadm --create --verbose --level=$RAIDLEVEL $MDDEV --name=$RAIDNAME --raid-devices=$NUM_DEVICES ${DEVICES[@]}
        mdadm --wait $MDDEV || true
        mdadm --detail --scan >> /etc/mdadm.conf
        blockdev --setra 65536 /dev/md0
        echo $((30*1024)) > /proc/sys/dev/raid/speed_limit_min
    )
fi

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
    error "The mount point $MOUNTPOINT did not come up, aborting"
fi

