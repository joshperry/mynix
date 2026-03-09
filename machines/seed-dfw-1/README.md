# seed-dfw-1

Primary seed cluster server. Bootstraps the k3s HA cluster with embedded etcd.

| Field | Value |
|-------|-------|
| Provider | Vultr bare-metal |
| Plan | vbm-6c-32gb (6 core, 32GB RAM, 2x960GB SSD) |
| Region | DFW (Dallas) |
| IPv4 | 216.128.140.15 |
| Reserved IPv4 | 216.128.141.222 (MetalLB LoadBalancer) |
| IPv6 | 2001:19f0:6402:d0a:3eec:efff:feb9:c20a |
| Reserved IPv6 | 2001:19f0:6402:7eb::/64 (MetalLB LoadBalancer) |
| Role | k3s server (etcd bootstrap), Ceph MON/MGR/OSD |
| Disks | sda: LUKS+btrfs (OS), sdb: Ceph OSD (dmcrypt) |
| SSH | `ssh seed-dfw-1` |

Runs the seed-controller Deployment and seed-host-agent DaemonSet.
