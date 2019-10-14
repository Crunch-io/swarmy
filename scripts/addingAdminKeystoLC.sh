#!/bin/bash
#adding keys to existing users via LC
tmpfile=$(mktemp) || { echo "Failed to create temp file"; exit 1; }
curl ${URL_KEYS[@]} --output $tmpfile
for i in ${USER_ARGS[@]} ; do
    if grep -q "$i" /etc/passwd; then
      cat $tmpfile >> /home/$i/.ssh/authorized_keys
    else
        echo "User $i Not Found"
    fi
done
#remove the tmpfile
rm -f $tmpfile
