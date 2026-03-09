# seed-dfw-3

Third seed cluster server. Joins the k3s HA cluster as a server (control plane).

| Field | Value |
|-------|-------|
| Provider | Vultr bare-metal |
| Plan | vbm-6c-32gb (6 core, 32GB RAM, 2x960GB SSD) |
| Region | DFW (Dallas) |
| IPv4 | 45.76.239.250 |
| IPv6 | 2001:19f0:6401:a11:3eec:efff:feb9:84bc |
| IPv6 gateway | fe80::63f:72ff:fe74:47bc |
| Role | k3s server, Ceph MON/MGR/OSD |
| Disks | sda: LUKS+btrfs (OS), sdb: Ceph OSD (dmcrypt) |
| SSH | `ssh seed-dfw-3` |
| Vultr ID | e16a2b61-0c12-4aff-8c14-6945561852cf |
