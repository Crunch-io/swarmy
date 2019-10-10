#!/bin/bash
#adding new user to LC and adding keys.

adduser -m -s /bin/bash --uid $uid $username
echo "$username ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
mkdir -p /home/$username/.ssh
curl https://dev.crunch.io/public/admkeys --output /tmp/keys
cat /tmp/keys >> /home/$username/.ssh/authorized_keys

#adding admin keys to existing users via LC

USER_NAME=($username1 $username2 $username3)
for i in ${USER_NAME[@]} ; do
    if grep -q "$i" /etc/passwd; then
      cat /tmp/keys >> /home/${USER_NAME}/.ssh/authorized_keys
    else 
        echo "User $i Not Found"
    fi
done
