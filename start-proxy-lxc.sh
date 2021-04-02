sudo lxc-stop --name lan
sudo lxc-copy --name lan -s --newname ceo
sudo lxc-start --name lan
sudo lxc-start --name ceo
