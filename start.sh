#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

# Attention, il se peut qu'ils existent déjà
brctl addbr sw-dmz &> /dev/null
brctl addbr sw-lan &> /dev/null
brctl addbr sw-ext &> /dev/null
ip link set sw-dmz up
ip link set sw-lan up
ip link set sw-ext up

ifup eth0 &> /dev/null
ifup sw-ext &> /dev/null

clist="fw dmz dmz2 lan ext"

for c in $clist
do
  echo "Démarrage de $c"
  lxc-start --name $c
done

# Sur ext, il faut encore configurer la table
# de routage avec l'IP du firewall

echo -n "Configuration de ext "

# Récupérer l'IP du firewall côté ext
gw=""
while [ "$gw" == "" ]
do
  echo -n "."
  sleep 2
  # Récupérer l'IP du firewall sur la patte 'extérieure'
  gw=$(lxc-attach --name fw -- ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)
done

echo -n " "

# Attendre que la config IP de ext soit prête
ip=""
while [ "$ip" == "" ]
do
  echo -n "."
  sleep 2
  ip=$(lxc-attach --name ext -- ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)
done

echo ""

sleep 1

lxc-attach --name ext -- /bin/bash -c "ip route add 203.0.113.0/24 via $gw"

lxc-attach --name ext -- /bin/bash -c "ip route add 192.0.2.0/24 via $gw"

#lxc-attach --name ext -- /bin/bash -c "ifdown eth0" &> /dev/null

lxc-attach --name ext -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
  up ip route add 203.0.113.0/24 via $gw
  down ip route add 203.0.113.0/24 via $gw
  up ip route add 192.0.2.0/24 via $gw
  down ip route add 192.0.2.0/24 via $gw
EOF

#lxc-attach --name ext -- /bin/bash -c "ifup eth0" &> /dev/null
