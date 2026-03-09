# seed-dfw-3

Third seed cluster server. Joins the k3s HA cluster as a server (control plane).

| Field | Value |
|-------|-------|
| Provider | Vultr bare-metal |
| Plan | vbm-6c-32gb (6 core, 32GB RAM, 2x960GB SSD) |
| Region | DFW (Dallas) |
| IPv4 | TBD (after provisioning) |
| IPv6 | TBD (after provisioning) |
| Role | k3s server, Ceph MON/MGR/OSD |
| Disks | sda: LUKS+btrfs (OS), sdb: Ceph OSD (dmcrypt) |
| SSH | `ssh seed-dfw-3` (after provisioning) |
