#!/bin/bash

if [ $EUID -ne 0 -o $# -ne 1 ]
then
  echo "sudo $0 user@container"
  exit
fi

user=$(echo $1 | cut -d '@' -f 1)
conteneur=$(echo $1 | cut -d '@' -f 2)

if [ "$user" == "root" ]
then
  lxc-attach --name $conteneur
else
  lxc-attach --name $conteneur -- /bin/bash -c "cd /home/$user; su $user"
fi
