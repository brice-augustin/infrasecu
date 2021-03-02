#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

clist="fw dmz dmz2 lan ext"

for c in $clist
do
  echo "Stop $c"
  lxc-stop --name $c
done
