#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi
# added ceo and sysadmin
clist="fw dmz dmz2 lan proxy ext ceo sysadmin"

for c in $clist
do
  echo "Stop $c"
  lxc-stop --name $c
done
