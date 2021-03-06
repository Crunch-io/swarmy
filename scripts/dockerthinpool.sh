#!/bin/bash -e

# This script is meant to be chained after prepephemeral.sh, other scripts like
# mountephemeral.sh can be used in a chain loaded fashion to then format and
# mount the new scratchspace that lives on LVM as a logical volume.

VGNAME=${VGNAME:-data}
DOCKERPERCENT=${DOCKERPERCENT:-50}

# 1% of the VG is already used by the thinpool meta, so the max number here is
# 49 assuming you leave DOCKERPERCENT at 50. Start small and you can always
# grow the logical volume later if necessary (lvextend)
SCRATCHPERCENT=${SCRATCHPERCENT:-25}

if [ -z "$SWARMYDIR" ]; then
    echo "SWARMYDIR is not set, this script should be run from swarmy. Cowardly refusing to continue."
    exit 1
fi

if [ ! -f "$SWARMYDIR/ephemeraldev" ]; then
    echo "$SWARMYDIR/ephemeraldev does not exist, not sure where to format/mount"
    exit 1
fi

DEVICE=$(cat $SWARMYDIR/ephemeraldev)

if [ ! -b $DEVICE ]; then
    echo "The device \"$DEVICE\" is not a block device. Cowardly refusing to continue"
    exit 1
fi

if ! command -v lvm > /dev/null; then
    echo "Please make sure that lvm and device-mapper-persistent-data are installed"
    exit 1
fi

if ! vgdisplay $VGNAME; then
    vgcreate $VGNAME $DEVICE
    lvcreate --wipesignatures y -n thinpool $VGNAME -l ${DOCKERPERCENT}%VG
    lvcreate --wipesignatures y -n thinpoolmeta $VGNAME -l 1%VG

    lvconvert -y --zero n -c 512K --thinpool $VGNAME/thinpool --poolmetadata $VGNAME/thinpoolmeta

    cat << EOF > /etc/lvm/profile/docker-thinpool.profile
activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
EOF

    lvchange --metadataprofile docker-thinpool $VGNAME/thinpool
    lvs -o+seg_monitor

    echo "Completed creation of the Docker thinpool"

    lvcreate --wipesignatures y -n scratch $VGNAME -l ${SCRATCHPERCENT}%VG

    echo "Created scratch space"

    echo -n "/dev/mapper/$VGNAME-scratch" > $SWARMYDIR/ephemeraldev
else
    echo "Physical volume already exists on: $DEVICE"
    echo "Doing nothing."
fi

touch $SWARMYDIR/dockerthinpool.run

