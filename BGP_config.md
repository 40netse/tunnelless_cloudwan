# BGP Configuration Reference — Tunnelless Cloud WAN

This document shows the complete BGP configuration on both sides of each
peering session: the AWS Cloud WAN Core Network Edge (CNE) and the FortiGate.

---

## Overview

```
  us-east-1                                          us-west-2
  ─────────────────────────────────────────────────────────────────
  FortiGate Primary   ←──eBGP──→  CNE East (ASN 64512)
  ASN 65000                        │
  port2: 10.1.3.10                 │   Cloud WAN backbone
  BGP peer: 10.1.3.1               │
                                   ↕
  FortiGate Secondary ←──eBGP──→  CNE West (ASN 64513)
  ASN 65000                        │
  port2: 10.11.3.10                │
  BGP peer: 10.11.3.1              │
  (west primary)                   │
```

Each FortiGate establishes one eBGP session with its local CNE. There is no
BGP session between FortiGates directly; inter-region route distribution is
handled by Cloud WAN's backbone.

---

## Cloud WAN Side (declarative — no CLI)

Cloud WAN BGP is configured entirely through Terraform resources. There is no
console or CLI configuration on the AWS side.

### Core Network Policy — edge location ASNs

```json
"core-network-configuration": {
  "asn-ranges": ["64512-65534"],
  "edge-locations": [
    { "location": "us-east-1", "asn": 64512 },
    { "location": "us-west-2", "asn": 64513 }
  ]
}
```

### Connect Peers — tells the CNE what ASN to expect from each FortiGate

| Peer name               | FortiGate IP  | FortiGate ASN | Subnet             |
|-------------------------|---------------|---------------|--------------------|
| east-fgt-primary-peer   | 10.1.3.10     | 65000         | 10.1.3.0/24 (AZ1)  |
| east-fgt-secondary-peer | 10.1.4.10     | 65000         | 10.1.4.0/24 (AZ2)  |
| west-fgt-primary-peer   | 10.11.3.10    | 65000         | 10.11.3.0/24 (AZ1) |
| west-fgt-secondary-peer | 10.11.4.10    | 65000         | 10.11.4.0/24 (AZ2) |

Protocol: `NO_ENCAP` (tunnel-less — no GRE, no IPsec).  
`inside_cidr_blocks` is omitted; AWS assigns `0.0.0.0/0` automatically.

### Route distribution

Cloud WAN automatically distributes BGP-learned routes within the `production`
segment (`isolate-attachments: false`). No explicit `segment-actions` is
required. Routes advertised by east FortiGates are visible to west attachments
and vice versa.

---

## FortiGate Side

### BGP neighbor IP

For `NO_ENCAP`, the CNE BGP IP is the **first IP of the inspection private
subnet** (the AWS VPC router address) — not a 169.254.x.x link-local address.

| FortiGate               | port2 IP   | CNE BGP peer | CNE ASN |
|-------------------------|------------|--------------|---------|
| East primary            | 10.1.3.10  | 10.1.3.1     | 64512   |
| East secondary          | 10.1.4.10  | 10.1.4.1     | 64512   |
| West primary            | 10.11.3.10 | 10.11.3.1    | 64513   |
| West secondary          | 10.11.4.10 | 10.11.4.1    | 64513   |

### East primary FortiGate — rendered BGP config

```
config router bgp
    set as 65000
    set router-id 10.1.3.10
    config neighbor
        edit "10.1.3.1"
            set remote-as 64512
            set soft-reconfiguration enable
            set ebgp-enforce-multihop enable
            set ebgp-multihop-ttl 255
            set update-source "port2"
        next
    end
    config network
        edit 1
            set prefix 10.2.0.0 255.255.0.0
        next
        edit 2
            set prefix 10.3.0.0 255.255.0.0
        next
    end
end
```

### East secondary FortiGate — rendered BGP config

```
config router bgp
    set as 65000
    set router-id 10.1.4.10
    config neighbor
        edit "10.1.4.1"
            set remote-as 64512
            set soft-reconfiguration enable
            set ebgp-enforce-multihop enable
            set ebgp-multihop-ttl 255
            set update-source "port2"
        next
    end
    config network
        edit 1
            set prefix 10.2.0.0 255.255.0.0
        next
        edit 2
            set prefix 10.3.0.0 255.255.0.0
        next
    end
end
```

### West primary FortiGate — rendered BGP config

```
config router bgp
    set as 65000
    set router-id 10.11.3.10
    config neighbor
        edit "10.11.3.1"
            set remote-as 64513
            set soft-reconfiguration enable
            set ebgp-enforce-multihop enable
            set ebgp-multihop-ttl 255
            set update-source "port2"
        next
    end
    config network
        edit 1
            set prefix 10.12.0.0 255.255.0.0
        next
        edit 2
            set prefix 10.13.0.0 255.255.0.0
        next
    end
end
```

### West secondary FortiGate — rendered BGP config

```
config router bgp
    set as 65000
    set router-id 10.11.4.10
    config neighbor
        edit "10.11.4.1"
            set remote-as 64513
            set soft-reconfiguration enable
            set ebgp-enforce-multihop enable
            set ebgp-multihop-ttl 255
            set update-source "port2"
        next
    end
    config network
        edit 1
            set prefix 10.12.0.0 255.255.0.0
        next
        edit 2
            set prefix 10.13.0.0 255.255.0.0
        next
    end
end
```

### Notes on FortiGate BGP settings

- **`ebgp-enforce-multihop`** — enabled with TTL 255. The session is single-hop
  (FortiGate and CNE are in the same subnet), so multihop is not strictly
  required but does not hurt.
- **`update-source port2`** — ensures BGP packets originate from the port2 IP
  that was registered as `peer_address` in the Connect Peer. Required.
- **`soft-reconfiguration enable`** — allows `clear bgp` without session reset
  for troubleshooting.
- **`router-id`** — set to the port2 IP to make it deterministic and unique
  across the HA pair.

---

## What each FortiGate advertises vs. receives

| FortiGate  | Advertises to CNE            | Receives from CNE (via backbone)   |
|------------|------------------------------|------------------------------------|
| East (both)| 10.2.0.0/16, 10.3.0.0/16    | 10.12.0.0/16, 10.13.0.0/16         |
| West (both)| 10.12.0.0/16, 10.13.0.0/16  | 10.2.0.0/16, 10.3.0.0/16           |

Cloud WAN distributes routes learned from east Connect Peers to west
attachments and vice versa. The spoke VPCs use a `0.0.0.0/0` default route
pointing to the core network ARN; Cloud WAN selects the correct next hop
based on the BGP-learned prefixes.

---

## Verification commands (FortiGate CLI)

```
# BGP session state
get router info bgp summary

# Routes received from Cloud WAN CNE
get router info bgp neighbors <cne_bgp_ip> received-routes

# Routes advertised to Cloud WAN CNE
get router info bgp neighbors <cne_bgp_ip> advertised-routes

# Routing table
get router info routing-table all
```

Expected: neighbors in `Established` state, remote spoke CIDRs visible in
received-routes, local spoke CIDRs visible in advertised-routes.
