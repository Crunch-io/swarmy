#!/bin/bash
#adding admin keys to existing users via LC
curl https://dev.crunch.io/public/admkeys --output /tmp/keys
for i in ${USER_ARGS[@]} ; do
    if grep -q "$i" /etc/passwd; then
      cat /tmp/keys >> /home/$i/.ssh/authorized_keys
    else 
        echo "User $i Not Found"
    fi
done
