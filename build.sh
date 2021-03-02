#!/bin/bash

# 17/2/2021 update pour LXC 3.0 (Debian Buster)
# https://discuss.linuxcontainers.org/t/lxc-3-0-0-has-been-released/1449
# Passage à Buster entraine instabilités : perte IP sur eth1,
# parfois "Stop job running" pendant 90s avant reboot ... :-(

# Si lancé dans VirtualBox, il faut une carte en Accès par pont + Allow All
# ou en NAT

# Ne PAS copier-coller dans nano, avec moba
# Glisser dans arborescence à gauche de moba

# TODO
# désinstaller openssh-server sur certains conteneurs
# Autoriser login root ssh, changer mdp root
# ... ou créer utilisateur etudiant plutôt non ?!

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

version=$(cat /etc/debian_version | cut -d '.' -f 1)

advinfra=1

if [ $version -ne 9 -a $version -ne 10 ]
then
  echo "Unsupported LXC version"
  exit
fi

# Capture SSH depuis Wireshark :
# sudo lxc-attach --name fw -- tcpdump -U -i eth2 -w -

function debianbase()
{
  lxc-create -n debianbase -t debian

  if [ $version -eq 9 ]
  then
    confkey="lxc.network"
  elif [ $version -eq 10 ]
  then
    confkey="lxc.net.0"
  fi

  echo "$confkey.type = veth" >> /var/lib/lxc/debianbase/config
  echo "$confkey.name = eth0" >> /var/lib/lxc/debianbase/config
  echo "$confkey.link = sw-ext" >> /var/lib/lxc/debianbase/config

  # XXX LXC 3.0
  #lxc-update-config -c /var/lib/lxc/debianbase/config

  lxc-start --name debianbase

  # Wait for container to be ready?
  sleep 1

  lxc-attach --name debianbase -- ifdown eth0

  lxc-attach --name debianbase -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
EOF

  lxc-attach --name debianbase -- ifup eth0

  lxc-attach --name debianbase -- /bin/bash -c "apt update -y" &> /dev/null
  # syslog-ng ?
  lxc-attach --name debianbase -- /bin/bash -c "apt-get install -y iputils-ping dnsutils nano tcpdump curl whois netcat" &> /dev/null

  lxc-stop -n debianbase
}

####
# Packages
####
apt -y update

# WireGuard doit être installé sur l'hôte pour fonctionner dans les conteneurs,
# sinon "unsupported operation" ... XXX Comprendre pourquoi
# Update du noyau. Attention le nouveau noyau ne sera utilisé qu'après un reboot !
apt -y install linux-image-amd64
# WireGuard est dans unstable
cat > /etc/apt/sources.list.d/unstable.list << EOF
deb http://deb.debian.org/debian/ unstable main
EOF

apt -y update

cat > /etc/apt/preferences.d/limit-unstable << EOF
Package: *
Pin: release a=unstable
Pin-Priority: 90
EOF

apt -y update

apt -y install wireguard

apt -y install lxc

brctl addbr sw-dmz &> /dev/null
brctl addbr sw-lan &> /dev/null
brctl addbr sw-ext &> /dev/null
ip link set sw-dmz up
ip link set sw-lan up
ip link set sw-ext up

ifdown eth0
sed -i '/eth0/d' /etc/network/interfaces

cat >> /etc/network/interfaces << EOF
auto eth0
iface eth0 inet manual
auto sw-ext
iface sw-ext inet dhcp
  pre-up brctl addif sw-ext eth0
  post-down brctl delif sw-ext eth0
EOF

ifup eth0
ifup sw-ext

####
#
####
echo "--- Building base container ---"
debianbase

####
# Firewall
####

cname="fw"
echo "--- Building $cname ---"

lxc-copy --name debianbase -s --newname fw

# Attention, conflit d'adresse MAC si plusieurs maquettes d'étudiants
# Mais LXC change d'adresse MAC à chaque démarrage :-(
#echo "lxc.network.hwaddr = 00:fa:da:fa:da:da" >> /var/lib/lxc/$cname/config

if [ $version -eq 9 ]
then
  confkey1="lxc.network"
  confkey2=$confkey1
elif [ $version -eq 10 ]
then
  confkey1="lxc.net.1"
  confkey2="lxc.net.2"
fi

echo "$confkey1.type = veth" >> /var/lib/lxc/$cname/config
echo "$confkey1.name = eth1" >> /var/lib/lxc/$cname/config
echo "$confkey1.link = sw-dmz" >> /var/lib/lxc/$cname/config

echo "$confkey2.type = veth" >> /var/lib/lxc/$cname/config
echo "$confkey2.name = eth2" >> /var/lib/lxc/$cname/config
echo "$confkey2.link = sw-lan" >> /var/lib/lxc/$cname/config

lxc-start --name $cname

sleep 1

lxc-attach --name $cname -- /bin/bash -c "apt-get install -y iptables" &> /dev/null

#lxc-attach --name $cname -- ifdown eth0

if [ $advinfra -eq 1 ]
then
  lxc-attach --name $cname -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
EOF

  lxc-attach --name $cname -- /bin/bash -c "cat >> /etc/network/interfaces" << EOF
auto eth0
iface eth0 inet dhcp
EOF

  lxc-attach --name $cname -- /bin/bash -c "cat >> /etc/network/interfaces" << EOF
auto eth1
iface eth1 inet static
  address 203.0.113.1/24
auto eth2
iface eth2 inet static
  address 192.0.2.1/24
EOF
fi

#lxc-attach --name $cname -- /bin/bash -c "cat > /etc/resolv.conf" <<< "nameserver 192.168.0.254"
# marche pas !
# LXC change pas MAC à chaque démarrage. Et VirtualBox ne maintient pas les IP
# entre deux redémarrages (?)
#fwextip=$(lxc-attach --name $cname -- ip a show dev eth0 | grep "inet " | awk '{print $2}' | cut -d '/' -f 1)

#lxc-attach --name $cname -- ip a show dev eth0
#echo $fwextip

#lxc-attach --name $cname -- ifup eth0

if [ $advinfra -eq 1 ]
then
  lxc-attach --name $cname -- sed -E -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
fi

# Test pour comprendre pourquoi l'IP ext change entre le build et le start
#ifdown eth0
#ifup eth0

# Récupérer l'IP du firewall sur la patte 'extérieure'
# Inutile à ce stade, l'IP va changer ...
#gw=$(lxc-attach --name $cname -- ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)

#lxc-attach --name $cname -- ip a show dev eth0

#echo "IP extérieure du firewall : $gw"

lxc-attach --name $cname -- /bin/bash -c 'pw=$(mkpasswd vitrygtr); useradd -p $pw admin -s /bin/bash -m'

lxc-stop -n $cname

####
# Web3 (EXT)
####
cname="ext"
echo "--- Building $cname ---"

lxc-copy --name debianbase -s --newname $cname
lxc-start --name $cname

if [ $advinfra -eq 1 ]
then
  # Attendre d'avoir une IP ... (?)
  sleep 5
  
  lxc-attach --name $cname -- /bin/bash -c "apt-get install -y apache2" &> /dev/null

  lxc-attach --name $cname -- /bin/bash -c "cat > /var/www/html/index.html" << EOF
<html><head><title>Welcome to EXT website</title></head>
<body>Welcome to EXT website</body></html>
EOF
fi

#lxc-attach --name $cname -- ifdown eth0

# XXX La configuration IP sera réalisée au démarrage (au moment où on
# connait l'IP du firewall)

#lxc-attach --name $cname -- ifup eth0

lxc-attach --name $cname -- /bin/bash -c 'pw=$(mkpasswd vitrygtr); useradd -p $pw hacker -s /bin/bash -m'

lxc-stop -n $cname


####
# Web1 (DMZ)
####

cname="dmz"
echo "--- Building $cname ---"

lxc-copy --name debianbase -s --newname $cname
lxc-start --name $cname

# Attendre d'avoir une IP ... (?)
sleep 5

if [ $advinfra -eq 1 ]
then

  # Install packages while we have direct access to the real internet
  lxc-attach --name $cname -- /bin/bash -c "apt-get install -y apache2" &> /dev/null

  lxc-attach --name $cname -- /bin/bash -c "cat > /var/www/html/index.html" << EOF
<html><head><title>Welcome to DMZ website</title></head>
<body>Welcome to DMZ website</body></html>
EOF

#lxc-attach --name $cname -- ifdown eth0

  lxc-attach --name $cname -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 203.0.113.10/24
  gateway 203.0.113.1
iface eth0 inet static
  address 203.0.113.11/24
iface eth0 inet static
  address 203.0.113.12/24
iface eth0 inet static
  address 203.0.113.13/24
iface eth0 inet static
  address 203.0.113.14/24
iface eth0 inet static
  address 203.0.113.15/24
iface eth0 inet static
  address 203.0.113.16/24
iface eth0 inet static
  address 203.0.113.17/24
iface eth0 inet static
  address 203.0.113.18/24
iface eth0 inet static
  address 203.0.113.19/24
EOF

  #lxc-attach --name $cname -- ifup eth0
fi

lxc-attach --name $cname -- /bin/bash -c 'pw=$(mkpasswd vitrygtr); useradd -p $pw admin -s /bin/bash -m'

lxc-stop -n $cname

sed -E -i 's/sw-ext/sw-dmz/' /var/lib/lxc/$cname/config

####
# Web2 (DMZ)
####

cname="dmz2"
echo "--- Building $cname ---"

lxc-copy --name dmz -s --newname $cname
lxc-start --name $cname

# Attendre d'avoir une IP ... (?)
sleep 5

if [ $advinfra -eq 1 ]
then

  lxc-attach --name $cname -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 203.0.113.30/24
  gateway 203.0.113.1
EOF

  lxc-attach --name $cname -- /bin/bash -c "cat > /var/www/html/index.html" << EOF
<html><head><title>Welcome to DMZ website (DMZ2)</title></head>
<body>Welcome to DMZ website (DMZ2)</body></html>
EOF
fi

lxc-stop -n $cname

####
# sysadmin (LAN)
####

cname="lan"
echo "--- Building $cname ---"

lxc-copy --name debianbase -s --newname $cname
lxc-start --name $cname

# Attendre d'avoir une IP ... (?)
sleep 5

# Install packages while we have direct access to the real internet
lxc-attach --name $cname -- /bin/bash -c "apt-get install -y curl" &> /dev/null

#lxc-attach --name $cname -- ifdown eth0

if [ $advinfra -eq 1 ]
then

  lxc-attach --name $cname -- /bin/bash -c "cat > /etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 192.0.2.100/24
  gateway 192.0.2.1
EOF
fi

#lxc-attach --name $cname -- ifup eth0

lxc-attach --name $cname -- /bin/bash -c 'pw=$(mkpasswd vitrygtr); useradd -p $pw admin -s /bin/bash -m'

lxc-stop -n $cname

sed -E -i 's/sw-ext/sw-lan/' /var/lib/lxc/$cname/config

echo "L'infra est prête ! Reboot (indispensable) dans 5 secondes ..."

sleep 5

reboot
