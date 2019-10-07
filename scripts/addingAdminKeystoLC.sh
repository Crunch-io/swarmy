#!/bin/bash
groupadd crunch -g 1002
useradd -m -s /bin/bash -c "Consistent user Crunch" -u 1002 -g 1002 crunch
echo "crunch ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
mkdir -p /home/crunch/.ssh
curl -H 'Authorization: token 3d1338272505a2084ca1b2b621f5f055d6c66bc4' -H 'Accept: application/vnd.github.v3.raw'   https://raw.githubusercontent.com/Crunch-io/zoom/master/pow/ansible/roles/common/files/sshkeys-admins.pub --output /tmp/keys
cat /tmp/keys >> /home/crunch/.ssh/authorized_keys
USER_NAME=(ec2-user centos ubuntu)
for i in ${USER_NAME[@]} ; do
    if grep -q "$i" /etc/passwd; then
      cat /tmp/keys >> /home/${USER_NAME}/.ssh/authorized_keys
    else
        echo "User $i Not Found"
    fi
done
