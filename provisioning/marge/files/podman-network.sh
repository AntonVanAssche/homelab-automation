sudo ip link add vlan1 link enp4s0 type macvlan mode bridge
sudo ip addr add 192.168.0.230/24 dev vlan1
sudo ip link set vlan1 up