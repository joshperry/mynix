# Seed Cluster Rebuild: 3-Node HA + FDE + Ceph

Disaster recovery runbook for the seed cluster. Covers provisioning from scratch:
Tang server, LUKS-encrypted nodes, k3s HA with embedded etcd, NixOS-native Ceph,
and ceph-csi for Kubernetes PVCs.

## Architecture

```
Tang VM ($6/mo, any Vultr region)
┌──────────────┐
│ services.tang│
│ port 7654    │
│ IP-restricted│
└──────┬───────┘
       │ Clevis LUKS auto-unlock
       ▼
seed-dfw-1 (server)     seed-dfw-2 (server)     seed-dfw-3 (server)
┌────────────────┐      ┌────────────────┐      ┌────────────────┐
│ sda: LUKS+btrfs│      │ sda: LUKS+btrfs│      │ sda: LUKS+btrfs│
│   Clevis/Tang  │      │   Clevis/Tang  │      │   Clevis/Tang  │
│ sdb: Ceph OSD  │      │ sdb: Ceph OSD  │      │ sdb: Ceph OSD  │
│   (dmcrypt)    │      │   (dmcrypt)    │      │   (dmcrypt)    │
│ k3s server     │      │ k3s server     │      │ k3s server     │
│ etcd member    │◄────►│ etcd member    │◄────►│ etcd member    │
│ ceph-mon/mgr   │      │ ceph-mon/mgr   │      │ ceph-mon/mgr   │
│ ceph-osd       │      │ ceph-osd       │      │ ceph-osd       │
└────────────────┘      └────────────────┘      └────────────────┘
```

Encryption chain: Tang → LUKS (sda, holds OS + mon DB) → Ceph dmcrypt (sdb, keys in mon DB)

## Prerequisites

- Vultr API key (at `/run/secrets/ada/vultr-api-key` on signi)
- Josh's PGP key for sops
- SSH access to signi as ada
- `nix`, `sops`, `age` CLI tools

## Node Inventory

| Node | IPv4 | IPv6 | Role | Hardware |
|------|------|------|------|----------|
| seed-tang-1 | TBD | - | Tang server | Vultr cloud VM ($6/mo) |
| seed-dfw-1 | 216.128.140.15 | 2001:19f0:6402:d0a:... | k3s server (etcd bootstrap) | vbm-6c-32gb, DFW |
| seed-dfw-2 | 104.238.146.15 | 2001:19f0:6401:2a5:... | k3s server | vbm-6c-32gb, DFW |
| seed-dfw-3 | TBD | TBD | k3s server | vbm-6c-32gb, DFW |

Reserved IPs:
- IPv4: 216.128.141.222 (LoadBalancer services)
- IPv6: 2001:19f0:6402:7eb::/64 (LoadBalancer services)

---

## Step 1: Provision Tang Server

Tang provides NBDE (Network-Bound Disk Encryption) — nodes auto-unlock LUKS
at boot by contacting Tang. If Tang is down, nodes fall back to passphrase prompt.

### 1.1 Create Vultr VM

```bash
# Cheapest Vultr cloud VM, any region
curl -s -X POST https://api.vultr.com/v2/instances \
  -H "Authorization: Bearer $(cat /run/secrets/ada/vultr-api-key)" \
  -H "Content-Type: application/json" \
  -d '{
    "region": "dfw",
    "plan": "vc2-1c-1gb",
    "os_id": 2284,
    "label": "seed-tang-1",
    "hostname": "seed-tang-1",
    "backups": "disabled"
  }'
```

Note the IP address from the response.

### 1.2 Deploy NixOS via nixos-anywhere

```bash
cd /agents/ada/projects/mynix

# Generate SSH host keys for sops integration
ssh-keygen -t ed25519 -f /tmp/seed-tang-1-host-key -N ""
# Extract age key: nix-shell -p ssh-to-age --run 'cat /tmp/seed-tang-1-host-key.pub | ssh-to-age'
# Add age key to .sops.yaml

# Deploy
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#seed-tang-1" \
  --extra-files /tmp/tang-keys \
  "root@<tang-ip>"
```

### 1.3 Verify Tang

```bash
ssh seed-tang-1 'systemctl status tangd.socket'
curl -sf http://<tang-ip>:7654/adv | jq .  # should return signing keys
```

### 1.4 Back Up Tang Keys

Tang keys are auto-generated on first start. Back them up — losing them means
all nodes need re-enrollment.

```bash
ssh seed-tang-1 'sudo tar czf - /var/db/tang/' > tang-keys-backup.tar.gz
# Store securely (encrypted, offline)
```

---

## Step 2: Provision seed-dfw-3

### 2.1 Create Bare-Metal Instance

```bash
curl -s -X POST https://api.vultr.com/v2/bare-metals \
  -H "Authorization: Bearer $(cat /run/secrets/ada/vultr-api-key)" \
  -H "Content-Type: application/json" \
  -d '{
    "region": "dfw",
    "plan": "vbm-6c-32gb",
    "os_id": 2284,
    "label": "seed-dfw-3",
    "hostname": "seed-dfw-3"
  }'
```

### 2.2 Generate Host Keys for sops

```bash
ssh-keygen -t ed25519 -f /tmp/seed-dfw-3-host-key -N ""
AGE_KEY=$(nix-shell -p ssh-to-age --run 'cat /tmp/seed-dfw-3-host-key.pub | ssh-to-age')
echo "seed-dfw-3 age key: $AGE_KEY"
# Add to mynix/.sops.yaml as &seed_dfw_3_age
```

### 2.3 Create sops Secrets File

```bash
cd /agents/ada/projects/mynix
# Create secrets/seed-dfw-3.yaml with k3s token
sops secrets/seed-dfw-3.yaml
# Add: seed/k3s-token: <token from seed-dfw-1:/var/lib/rancher/k3s/server/token>
```

### 2.4 Deploy via nixos-anywhere

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#seed-dfw-3" \
  --disk-encryption-keys /tmp/disk-password /tmp/luks-passphrase \
  "root@<dfw3-ip>"
```

---

## Step 3: LUKS + Clevis Binding (All Nodes)

Nodes are provisioned with a temporary LUKS passphrase. Bind to Tang for
auto-unlock, then optionally remove the passphrase slot.

### 3.1 Bind Clevis to Tang

Run on each seed node (dfw-1, dfw-2, dfw-3):

```bash
# Bind LUKS to Tang (adds a new key slot with Tang binding)
sudo clevis luks bind -d /dev/sda2 tang '{"url":"http://<tang-ip>:7654"}'

# Verify binding
sudo clevis luks list -d /dev/sda2
# Should show: 1: tang '{"url":"http://<tang-ip>:7654"}'
```

### 3.2 Save JWE for Initrd

```bash
# Extract the Clevis JWE token
sudo clevis luks list -d /dev/sda2 -s 2 > /tmp/clevis-jwe
sudo mkdir -p /persist/secrets
sudo cp /tmp/clevis-jwe /persist/secrets/clevis-cryptroot.jwe
sudo chmod 600 /persist/secrets/clevis-cryptroot.jwe
```

### 3.3 Rebuild with Clevis Initrd

```bash
# On the node:
sudo nixos-rebuild switch --flake github:joshperry/mynix#seed-dfw-X --refresh
```

### 3.4 Verify Auto-Unlock

```bash
sudo reboot
# Node should boot without passphrase prompt
# If Tang is unreachable, will prompt for passphrase on console
```

### 3.5 Optionally Remove Passphrase Slot

Only do this after verifying Tang auto-unlock works reliably:

```bash
sudo cryptsetup luksRemoveKey /dev/sda2
# Enter the temporary passphrase to remove it
```

---

## Step 4: Bootstrap k3s HA Cluster

Order matters — embedded etcd must be bootstrapped on one node first.

### 4.1 Bootstrap etcd on seed-dfw-1

seed-dfw-1 runs with `seed.k3s.clusterInit = true` which adds `--cluster-init`
to k3s, bootstrapping a single-node etcd cluster.

```bash
# Build and switch on seed-dfw-1
ssh seed-dfw-1 'sudo nixos-rebuild build --flake github:joshperry/mynix#seed-dfw-1 --refresh --show-trace'
ssh seed-dfw-1 'nvd diff /run/current-system result'
ssh seed-dfw-1 'sudo nix-env -p /nix/var/nix/profiles/system --set ./result && sudo ./result/bin/switch-to-configuration switch'
ssh seed-dfw-1 'unlink result'
```

Verify:
```bash
ssh seed-dfw-1 'sudo k3s kubectl get nodes'
# Should show seed-dfw-1 as Ready, control-plane
```

### 4.2 Get k3s Token

```bash
ssh seed-dfw-1 'sudo cat /var/lib/rancher/k3s/server/token'
# Use this token in seed-dfw-2 and seed-dfw-3 sops secrets
```

### 4.3 Join seed-dfw-2 as Server

seed-dfw-2's config has `role = "server"` + `serverAddr` + `tokenFile`.
This makes it join as a server (control plane) member, not just a worker.

```bash
ssh seed-dfw-2 'sudo nixos-rebuild build --flake github:joshperry/mynix#seed-dfw-2 --refresh --show-trace'
ssh seed-dfw-2 'nvd diff /run/current-system result'
ssh seed-dfw-2 'sudo nix-env -p /nix/var/nix/profiles/system --set ./result && sudo ./result/bin/switch-to-configuration switch'
ssh seed-dfw-2 'unlink result'
```

Verify:
```bash
ssh seed-dfw-1 'sudo k3s kubectl get nodes'
# Should show both seed-dfw-1 and seed-dfw-2 as Ready, control-plane
```

### 4.4 Join seed-dfw-3 as Server

Same process as seed-dfw-2.

### 4.5 Verify HA

```bash
ssh seed-dfw-1 'sudo k3s kubectl get nodes'
# All 3 nodes: Ready, control-plane

# Verify etcd health
ssh seed-dfw-1 'sudo k3s etcd-snapshot list'
```

### 4.6 Flip clusterInit Off

After all 3 servers are running, set `seed.k3s.clusterInit = false` on seed-dfw-1
and rebuild. The flag is only needed for initial bootstrap.

---

## Step 5: Ceph Bootstrap

NixOS services.ceph runs the daemons; initial cluster bootstrap is imperative.

### 5.1 Generate Cluster UUID

```bash
uuidgen
# Use this as fsid in seed-ceph.nix profile
```

### 5.2 Create Mon Keyring (on seed-dfw-1)

```bash
sudo ceph-authtool --create-keyring /tmp/ceph.mon.keyring \
  --gen-key -n mon. --cap mon 'allow *'

sudo ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring \
  --gen-key -n client.admin \
  --cap mon 'allow *' \
  --cap osd 'allow *' \
  --cap mgr 'allow *' \
  --cap mds 'allow *'

sudo ceph-authtool /tmp/ceph.mon.keyring \
  --import-keyring /etc/ceph/ceph.client.admin.keyring
```

### 5.3 Create Monitor Map

```bash
sudo monmaptool --create \
  --add seed-dfw-1 216.128.140.15 \
  --add seed-dfw-2 104.238.146.15 \
  --add seed-dfw-3 <dfw3-ip> \
  --fsid <uuid> \
  /tmp/monmap
```

### 5.4 Initialize Monitors

On seed-dfw-1:
```bash
sudo -u ceph mkdir -p /var/lib/ceph/mon/ceph-seed-dfw-1
sudo ceph-mon --mkfs -i seed-dfw-1 --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring
sudo systemctl start ceph-mon-seed-dfw-1
```

Copy keyrings to seed-dfw-2 and seed-dfw-3, then repeat mkfs + start on each.

### 5.5 Start Managers

On each node:
```bash
sudo -u ceph mkdir -p /var/lib/ceph/mgr/ceph-seed-dfw-X
sudo ceph auth get-or-create mgr.seed-dfw-X mon 'allow profile mgr' \
  osd 'allow *' mds 'allow *' > /var/lib/ceph/mgr/ceph-seed-dfw-X/keyring
sudo systemctl start ceph-mgr-seed-dfw-X
```

### 5.6 Prepare OSDs (with dmcrypt)

On each node:
```bash
sudo ceph-volume lvm create --dmcrypt --data /dev/sdb
```

This encrypts the OSD at the block level. The encryption keys are stored in
the Ceph monitor's key-value store (on LUKS-encrypted sda).

### 5.7 Verify Ceph

```bash
sudo ceph -s
# Should show:
#   health: HEALTH_OK
#   mon: 3 daemons
#   mgr: active + 2 standbys
#   osd: 3 osds: 3 up, 3 in
#   ~2.8 TiB raw capacity
```

### 5.8 Store Keyrings in sops

```bash
# Add keyrings to secrets/seed-system.yaml
sops secrets/seed-system.yaml
# Add: ceph/admin-keyring, ceph/mon-keyring
```

### 5.9 Create RBD Pool

```bash
sudo ceph osd pool create seed-pool 32 replicated
sudo ceph osd pool application enable seed-pool rbd
sudo rbd pool init seed-pool
```

---

## Step 6: Deploy ceph-csi

ceph-csi provides Kubernetes StorageClass backed by Ceph RBD.

### 6.1 Create ceph-csi Namespace

```bash
kubectl create namespace ceph-csi
```

### 6.2 Create Secrets

```bash
# Get Ceph cluster info
FSID=$(sudo ceph fsid)
MON_ENDPOINTS=$(sudo ceph mon dump -f json | jq -r '.mons | map(.public_addrs.addrvec[] | select(.type == "v2") | .addr) | join(",")')

# Create ceph-csi configmap
kubectl -n ceph-csi create configmap ceph-csi-config \
  --from-literal=config.json='[{"clusterID":"'$FSID'","monitors":["'$MON_ENDPOINTS'"]}]'

# Create secret for provisioner
ADMIN_KEY=$(sudo ceph auth get-key client.admin)
kubectl -n ceph-csi create secret generic csi-rbd-secret \
  --from-literal=userID=admin \
  --from-literal=userKey=$ADMIN_KEY
```

### 6.3 Deploy ceph-csi Manifests

Deploy via k3s auto-deploy manifests directory. The manifests include:
- RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- `csi-rbdplugin` DaemonSet (node plugin)
- `csi-rbdplugin-provisioner` Deployment (controller)
- StorageClass `ceph-rbd` (default)

NixOS-specific: DaemonSet pods need a hostPath mount for
`/run/current-system/kernel-modules/` to access the `rbd` kernel module.

### 6.4 Create StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: <fsid>
  pool: seed-pool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi
reclaimPolicy: Retain
allowVolumeExpansion: true
```

### 6.5 Verify

```bash
kubectl get sc
# ceph-rbd (default)

# Test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ceph-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-ceph-pvc
# Should be Bound

# Check RBD image
sudo rbd ls seed-pool
# Should show the image

kubectl delete pvc test-ceph-pvc
```

---

## Step 7: Migrate Workloads

### 7.1 Trigger Reconciliation

```bash
# Webhook trigger (or manual)
curl -X POST https://loom.farm/_hook/refresh
```

The controller will:
1. Eval flake paths
2. Build instances
3. Create Deployments with Ceph-backed PVCs (new default StorageClass)
4. Instances boot in Kata VMs

### 7.2 Verify Services

```bash
# All nodes control-plane
kubectl get nodes
# All pods running
kubectl get pods -A

# DNS
dig @216.128.141.222 loom.farm SOA
dig @2001:19f0:6402:7eb::1 loom.farm SOA

# HTTPS
curl -sI https://loom.farm

# Ceph health
sudo ceph -s
```

### 7.3 Test HA

```bash
# Cordon a node
kubectl cordon seed-dfw-2
kubectl drain seed-dfw-2 --ignore-daemonsets --delete-emptydir-data

# Verify workloads migrated
kubectl get pods -A -o wide

# Uncordon
kubectl uncordon seed-dfw-2

# Reboot test
ssh seed-dfw-2 'sudo reboot'
# Should auto-unlock LUKS via Tang and rejoin cluster
```

---

## Recovery Scenarios

### Tang Server Lost

1. Provision new Vultr VM
2. Restore Tang keys from backup: `tar xzf tang-keys-backup.tar.gz -C /`
3. Start Tang service
4. If Tang IP changed: re-bind Clevis on all nodes with new URL

If backup is also lost: enter passphrase on console for each node, then
re-generate Tang keys and re-bind.

### Single Node Lost

1. Provision new bare-metal instance (same plan, DFW)
2. Generate host keys, update sops
3. Deploy via nixos-anywhere with LUKS disks.nix
4. Bind Clevis to Tang
5. k3s auto-joins cluster (serverAddr + token in config)
6. `ceph-volume lvm create --dmcrypt --data /dev/sdb` for new OSD
7. Ceph rebuilds replicas automatically

### Full Cluster Lost

Follow this entire runbook from Step 1. Data on Ceph is lost (all 3 OSDs gone).
Instance PVC data must be recreated from scratch (nix rebuilds everything,
only mutable state like databases is lost).

### etcd Lost (All 3 Servers Down Simultaneously)

k3s with embedded etcd stores snapshots. Restore from snapshot:
```bash
# On one node:
sudo k3s server --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot>
```

Then join other nodes normally.

---

## Key Files

| File | Purpose |
|------|---------|
| `machines/seed-tang-1/configuration.nix` | Tang server config |
| `machines/seed-dfw-*/configuration.nix` | Node configs (k3s role, network, seed options) |
| `machines/seed-dfw-*/disks.nix` | LUKS disk layout |
| `profiles/seed-cache.nix` | S3 binary cache (shared by all seed nodes) |
| `profiles/seed-controller.nix` | Shared secrets for controller |
| `profiles/seed-ceph.nix` | Ceph cluster config |
| `secrets/seed-system.yaml` | Shared secrets (cache keys, Ceph keyrings) |
| `secrets/seed-dfw-*.yaml` | Per-node secrets (k3s token) |

## Important Notes

- Tang keys MUST be backed up. Losing them + all node passphrases = unrecoverable.
- Clevis JWE stored at `/persist/secrets/` — useless without Tang (DH exchange).
  Use string paths in NixOS config (not nix paths) to avoid nix store exposure.
- Ceph OSD dmcrypt keys live in mon DB (on LUKS-encrypted sda). The encryption
  chain is: Tang → LUKS → mon DB → OSD dmcrypt.
- k3s `--cluster-init` is only for the first server. Remove after cluster is up.
- Ceph bootstrap is imperative — NixOS module runs daemons, doesn't provision.
- `nix flake` cache TTL is ~3600s — use `--refresh` after pushing changes.
- Build on the server, not locally on signi.
