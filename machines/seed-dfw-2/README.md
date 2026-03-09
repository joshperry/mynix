# seed-dfw-2

Second seed cluster server. Joins the k3s HA cluster as a server (control plane).

| Field | Value |
|-------|-------|
| Provider | Vultr bare-metal |
| Plan | vbm-6c-32gb (6 core, 32GB RAM, 2x960GB SSD) |
| Region | DFW (Dallas) |
| IPv4 | 104.238.146.15 |
| IPv6 | 2001:19f0:6401:2a5:3eec:efff:feb9:8888 |
| Role | k3s server, Ceph MON/MGR/OSD |
| Disks | sda: LUKS+btrfs (OS), sdb: Ceph OSD (dmcrypt) |
| SSH | `ssh seed-dfw-2` |
| Vultr ID | 3db1e63c-c097-43f9-8bf2-19e26bf6756c |
