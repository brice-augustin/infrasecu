#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

ifdown sw-ext
sed -i '/sw-ext/d' /etc/network/interfaces
sed -i '/eth0/d' /etc/network/interfaces

ifdown eth0

cat >> /etc/network/interfaces << EOF
auto eth0
iface eth0 inet dhcp
EOF

sudo ifup eth0

ip link set sw-dmz down
ip link set sw-lan down
ip link set sw-ext down
brctl delbr sw-dmz
brctl delbr sw-lan
brctl delbr sw-ext

ip link set sw-ispfw down
brctl delbr sw-ispfw

ip link set sw-ispfiliale down
brctl delbr sw-ispfiliale

ip link set sw-filiale down
brctl delbr sw-filiale

# debianbase en dernier
clist="ext dmz2 dmz fw lan r1 r2 fil"

for c in $clist
do
  lxc-stop --name $c
  lxc-destroy --name $c
done

#exit

c="debianbase"
lxc-stop --name $c
lxc-destroy --name $c
