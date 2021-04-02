#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

####
# proxy (LAN)
####

cname="proxy"
echo "--- Building $cname ---"

lxc-copy --name debianbase -s --newname $cname
lxc-start --name $cname

# Attendre d'avoir une IP ... (?)
sleep 5

#lxc-attach --name $cname -- ifdown eth0

lxc-attach --name $cname -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 192.0.2.2/24
  gateway 192.0.2.1
EOF

#lxc-attach --name $cname -- ifup eth0

lxc-attach --name $cname -- /bin/bash -c 'pw=$(mkpasswd vitrygtr); useradd -p $pw admin -s /bin/bash -m'

lxc-stop -n $cname

sed -E -i 's/sw-ext/sw-lan/' /var/lib/lxc/$cname/config

echo "Demarrage de $cname"
lxc-start --name $cname
