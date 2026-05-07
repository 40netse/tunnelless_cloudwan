# Tunnelless CloudWAN — FortiGate + AWS Cloud WAN

Demonstrates AWS Cloud WAN **tunnel-less Connect** with FortiGate HA pairs in two regions. FortiGates peer with the Cloud WAN Core Network Edge (CNE) via native eBGP — no GRE, no IPsec between sites. AWS Cloud WAN is the WAN fabric.

---

## Architecture

```
┌─────────────────────── us-east-1 ──────────────────────────┐
│                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │  Spoke A VPC │   │  Spoke B VPC │   │ Inspection VPC │  │
│  │  10.2.0.0/16 │   │  10.3.0.0/16 │   │  10.1.0.0/16   │  │
│  │              │   │              │   │  ┌──────────┐   │  │
│  │  test inst.  │   │  test inst.  │   │  │FGT Primary│  │  │
│  └──────┬───────┘   └──────┬───────┘   │  │ (AZ1)    │  │  │
│         │ Cloud WAN         │ Cloud WAN │  │ port1/2/3│  │  │
│         │ VPC attach        │ VPC attach│  └──────────┘  │  │
│         │                   │           │  ┌──────────┐   │  │
│         └───────────────────┴───────────┤  │FGT Second│  │  │
│                                         │  │ (AZ2)    │  │  │
│                                         │  │ port1/2/3│  │  │
│                                         │  └──────────┘  │  │
│                                         │  VPC attach +  │  │
│                                         │  Connect attach│  │
│                                         │  (NO_ENCAP)    │  │
└─────────────────────────────────────────┴────────┬────────┘  │
                                                    │ eBGP      │
                              ┌─────────────────────┘           │
                              │   AWS Cloud WAN Core Network     │
                              │   Global backbone (no tunnels)   │
                              └─────────────────────┐           │
                                                    │ eBGP      │
┌─────────────────────── us-west-2 ──────────────────────────┐
│                                         ┌────────┴────────┐  │
│  ┌──────────────┐   ┌──────────────┐   │ Inspection VPC │  │
│  │  Spoke A VPC │   │  Spoke B VPC │   │  10.11.0.0/16  │  │
│  │  10.12.0.0/16│   │  10.13.0.0/16│   │  FGT Primary   │  │
│  │  test inst.  │   │  test inst.  │   │  FGT Secondary │  │
│  └──────┬───────┘   └──────┬───────┘   │  (same layout) │  │
│         │ VPC attach        │ VPC attach└────────────────┘  │
│         └───────────────────┘                                │
└──────────────────────────────────────────────────────────────┘
```

### Per-region inspection VPC detail

```
Inspection VPC
├── Public subnets (AZ1/AZ2)    — FortiGate port1, cluster EIP, IGW
├── Private subnets (AZ1/AZ2)   — FortiGate port2, Cloud WAN VPC attachment ENIs
└── HA sync subnets (AZ1/AZ2)   — FortiGate port3, management EIPs, EC2 VPC endpoint
```

### Traffic flow (spoke A east → spoke A west)

```
Spoke A (us-east-1)
  └─► Cloud WAN VPC attachment (east)
        └─► Core Network Edge (us-east-1)  ← FortiGate BGP advertises east spoke CIDRs
              └─► Cloud WAN backbone (AWS Global Network, no tunnels)
                    └─► Core Network Edge (us-west-2)
                          └─► Cloud WAN VPC attachment (west)
                                └─► Spoke A (us-west-2)
```

---

## Key components

| Resource | Count | Purpose |
|---|---|---|
| `aws_networkmanager_global_network` | 1 | Top-level Cloud WAN container |
| `aws_networkmanager_core_network` | 1 | Managed backbone, both regions |
| `aws_networkmanager_vpc_attachment` | 6 | Inspection + 2 spokes × 2 regions |
| `aws_networkmanager_connect_attachment` | 2 | NO_ENCAP per region (over inspection VPC attachment) |
| `aws_networkmanager_connect_peer` | 4 | One per FortiGate, eBGP to CNE |
| `aws_instance` (FortiGate) | 4 | HA primary + secondary × 2 regions |
| `aws_eip` | 6 | Cluster EIP + 2 mgmt EIPs × 2 regions |
| `aws_iam_role/policy` | 2 | HA failover — EIP reassignment |
| `aws_vpc_endpoint` (EC2 API) | 2 | HA failover without internet dependency |

---

## BGP design

```
FortiGate primary (us-east-1)   ASN 65000
  └─► eBGP neighbor 169.254.6.1 (CNE, ASN 64512)
        advertises: 10.2.0.0/16, 10.3.0.0/16

FortiGate secondary (us-east-1) ASN 65000
  └─► eBGP neighbor 169.254.6.9 (CNE, ASN 64512)
        advertises: 10.2.0.0/16, 10.3.0.0/16

FortiGate primary (us-west-2)   ASN 65000
  └─► eBGP neighbor 169.254.7.1 (CNE, ASN 64512)
        advertises: 10.12.0.0/16, 10.13.0.0/16

FortiGate secondary (us-west-2) ASN 65000
  └─► eBGP neighbor 169.254.7.9 (CNE, ASN 64512)
        advertises: 10.12.0.0/16, 10.13.0.0/16
```

Each FortiGate also installs static routes for its own local and remote spoke CIDRs via port2, and a static route to the CNE inside CIDR via port2 so the BGP session can be established.

### HA and BGP

Each FortiGate has its own Connect Peer and eBGP session with the CNE. The primary and secondary maintain independent BGP sessions. During FGCP failover, the new primary's BGP session takes over. FortiGate config sync via FGCP may overwrite per-unit BGP config — for production, use FortiManager to manage per-device BGP neighbor configuration.

---

## Prerequisites

- AWS account with Cloud WAN enabled
- EC2 key pairs in both `us-east-1` and `us-west-2`
- FortiGate PAYG AMI accessible (Fortinet Marketplace subscription)
- Terraform >= 1.5.0, AWS provider ~> 5.0

---

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set keypair names, passwords

terraform init
terraform plan
terraform apply
```

Cloud WAN Core Network provisioning takes ~10–15 minutes. Total deploy time is approximately 20–25 minutes.

---

## CIDR map

| VPC | Region | CIDR |
|---|---|---|
| Inspection | us-east-1 | 10.1.0.0/16 |
| Spoke A | us-east-1 | 10.2.0.0/16 |
| Spoke B | us-east-1 | 10.3.0.0/16 |
| Inspection | us-west-2 | 10.11.0.0/16 |
| Spoke A | us-west-2 | 10.12.0.0/16 |
| Spoke B | us-west-2 | 10.13.0.0/16 |

---

## Verify connectivity

After apply, SSH to a spoke test instance via the FortiGate cluster EIP and ping across regions:

```bash
# From spoke A test instance in us-east-1, ping spoke A test instance in us-west-2
ping 10.12.1.10

# Check FortiGate BGP status
diagnose ip router bgp all
get router info bgp summary
```

Expected BGP output on primary FortiGate:
```
Neighbor        V   AS   MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
169.254.6.1     4 64512      ...             ...              Established  4
```

---

## Destroy

```bash
terraform destroy
```

Cloud WAN attachment deletion can take several minutes. The Core Network and Global Network are deleted last.
