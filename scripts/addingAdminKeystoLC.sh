#!/bin/bash

#adding new user to LC and adding keys. 
#The arguments comes from the .profile as an array.
adduser -m -s /bin/bash --uid ${USER_ARGS[1]} ${USER_ARGS[0]}
echo "${USER_ARGS[0]} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
mkdir -p /home/${USER_ARGS[0]}/.ssh
curl https://dev.crunch.io/public/admkeys --output /tmp/keys
cat /tmp/keys >> /home/${USER_ARGS[0]}/.ssh/authorized_keys

#adding admin keys to existing users via LC
USER_NAME=(${USER_ARGS[2]} ${USER_ARGS[3]} ${USER_ARGS[4]})
for i in ${USER_NAME[@]} ; do
    if grep -q "$i" /etc/passwd; then
      cat /tmp/keys >> /home/${USER_NAME}/.ssh/authorized_keys
    else 
        echo "User $i Not Found"
    fi
done
