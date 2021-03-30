#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "sudo $0"
  exit
fi

clist="fil r1 r2 fw dmz2 dmz lan ext"

for c in $clist
do
  echo "Stop $c"
  lxc-stop --name $c
done
