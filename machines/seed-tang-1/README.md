# seed-tang-1

Tang server for Network-Bound Disk Encryption (NBDE). Seed nodes auto-unlock
LUKS at boot by contacting this server.

| Field | Value |
|-------|-------|
| Provider | Vultr cloud VM |
| Plan | vc2-1c-1gb ($6/mo) |
| Region | DFW (Dallas) |
| IPv4 | TBD (after provisioning) |
| Role | Tang NBDE server |
| Port | 7654 (TCP, IP-restricted to seed node subnets) |
| SSH | `ssh seed-tang-1` (after provisioning) |

Tang keys are auto-generated on first start. Back up `/var/db/tang/` — losing
these keys means all nodes need re-enrollment.
