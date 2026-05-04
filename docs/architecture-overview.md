# Architecture overview

## High-level

```
                          PUBLIC INTERNET
                              |
              +---------------+-----------------+
              |                                 |
    Public DNS zone exepron.com         Azure VPN Gateway
    (app.exepron.com -> public IP)      ExepronVPN
    (sales/admin/* NOT here)            Standard Public IP
              |                                 |
              |                  encrypted P2S tunnel (cert auth)
              |                                 |
              |                         +-------+----------------------------+
              |                         | VNet: Exepron-vnet                  |
              |                         | Address space: 172.16.0.0/16        |
              |                         | VPN client pool: 172.100.1.0/24     |
              |                         |                                     |
              |                         |  +---- DNS server ---+               |
              |                         |  | 172.16.10.11      |               |
              |                         |  | Windows DNS role  |               |
              |                         |  | Forwards -> 168.63.129.16          |
              |                         |  +-------+-----------+               |
              |                         |          |                          |
              |                         |          v                          |
              |                         |  Azure-provided DNS                  |
              |                         |  168.63.129.16                       |
              |                         |          |                          |
              |                         |          v                          |
              |                         | Private DNS zone exepron.com         |
              |                         |   (linked to this VNet)              |
              |                         |   sales      -> 172.16.1.4           |
              |                         |   salestest  -> 172.16.10.11         |
              |                         |   admin      -> 172.16.1.4           |
              |                         |   admintest  -> 172.16.10.11         |
              |                         |                                     |
              |                         | Web servers:                         |
              |                         |   172.16.1.4   (sales/admin)         |
              |                         |   172.16.10.11 (test)                |
              |                         +-------------------------------------+
              |
              v
    Public users -> only public records
```

## Components

### Azure VPN Gateway (`ExepronVPN`)
- Type: Route-based, Point-to-Site, certificate authentication, OpenVPN + IKEv2.
- Migrated from Basic SKU to Standard SKU public IP (June 2026 deadline).
- Address pool for connected clients: `172.100.1.0/24`.
- Routes only `172.16.0.0/16` traffic through the tunnel.
- Trusted client root certs: `ExepronP2SRoot` (current). Old roots may be kept in parallel for legacy users until they're all migrated.

### Two `exepron.com` DNS zones (same name, different scope)

| Property | Public zone | Private zone |
|---|---|---|
| Type | DNS zone | Private DNS zone |
| Audience | Internet | Linked VNets only |
| Authoritative for outside world | Yes (delegated from registrar) | No |
| Records | `app.exepron.com`, etc. (public IPs) | `sales`, `salestest`, `admin`, `admintest` (private IPs in 172.16.0.0/16) |
| VNet link | N/A | `vpn-vnet-link` to `Exepron-vnet` |

The wildcard SSL cert `*.exepron.com` covers both zones because the cert is name-based, not IP-based.

### DNS forwarder at `172.16.10.11`
- Existing Windows server with the **DNS Server** role added.
- Configured to forward unknown queries to `168.63.129.16` (Azure-provided DNS).
- Why this server, not a new VM: zero cost addition.
- Why a forwarder at all, not point clients directly at `168.63.129.16`: that magic IP isn't reachable from VPN clients (`172.100.1.x`) without per-client route hacks. `172.16.10.11` is inside the routed subnet so VPN clients reach it naturally.

### Wildcard cert `*.exepron.com`
- Covers all one-label-deep names: `sales.exepron.com`, `app.exepron.com`, etc.
- Installed on `172.16.1.4` (sales/admin) and `172.16.10.11` (test).
- Browsers don't care which IP the name resolves to; they validate against the URL hostname.

## Two example flows

### Public user visits `https://app.exepron.com`

1. Browser asks public DNS for `app.exepron.com`.
2. Public DNS returns the public IP (e.g. `20.127.170.148`).
3. Browser opens TCP/443.
4. Wildcard cert validates. Page loads. (No VPN involved.)

### VPN-connected user visits `https://sales.exepron.com`

1. User connects VPN. Gateway issues their device an IP from `172.100.1.0/24`. VPN profile pushes DNS = `172.16.10.11` and routes `172.16.0.0/16` through tunnel.
2. Browser asks DNS (`172.16.10.11`) for `sales.exepron.com`.
3. Query packet enters tunnel (target IP is in routed range), reaches the DNS forwarder.
4. Forwarder doesn't know that record locally → forwards to `168.63.129.16`.
5. `168.63.129.16` sees the linked private zone, returns `172.16.1.4`.
6. Answer travels back to user's device through tunnel.
7. Browser opens TCP/443 to `172.16.1.4`. Tunnel routes that packet too (in routed range).
8. Web server at `172.16.1.4` responds with the wildcard cert. Browser validates because URL is `sales.exepron.com` and `*.exepron.com` covers it.
9. Page loads. To anyone outside the VPN, `sales.exepron.com` does not resolve at all (no public record).

## Client architecture

| Platform | Client app | Profile format | Cert delivery |
|---|---|---|---|
| macOS | OpenVPN Connect (App Store) | `.ovpn` with embedded cert+key | Single `.ovpn` file |
| iOS / iPadOS | OpenVPN Connect (App Store) | `.ovpn` with embedded cert+key | Single `.ovpn` file |
| Windows | OpenVPN Connect | `.ovpn` with embedded cert+key | Single `.ovpn` file |

Same `.ovpn` works on every platform. The admin generates per-user `.ovpn` files using the scripts in this repo.

## Key design decisions

| Decision | Why |
|---|---|
| Same name (`exepron.com`) for public + private zones | Wildcard cert `*.exepron.com` only covers one label deep. Putting internal hosts at `sales.internal.exepron.com` would require a new wildcard cert. |
| DNS forwarder, not Azure DNS Private Resolver | Cost — zero extra spend vs. ~$160/month for the managed Private Resolver. Tradeoff: must maintain the Windows DNS role. |
| DNS forwarder at `172.16.10.11`, not `168.63.129.16` directly | The magic IP isn't routable from VPN clients without manually adding a custom route per client. A forwarder at `172.16.x.x` is automatically reachable through the existing VPN route, no per-client config. |
| OpenVPN Connect across all platforms (not Azure VPN Client) | Azure VPN Client has a known cert-dropdown bug with self-signed roots; OpenVPN Connect handles them reliably. Same client on every platform reduces support load. |
| Self-contained `.ovpn` per user (cert+key embedded) | One file per user, no separate Keychain/profile install. Simple distribution model. Tradeoff: if a `.ovpn` leaks, the private key leaks with it (revocable via Azure Revoked Certificates list). |
| Removed internal A records from public zone | Public DNS shouldn't advertise RFC1918 IPs. Triggers DNS rebinding filters on customer networks, and the IPs aren't routable from the public internet anyway. |

## What this architecture gives you

- One DNS name per service (no `sales.exepron.com` + `sales.internal.exepron.com` split).
- One wildcard cert for everything.
- Internal hosts invisible from the public internet (NXDOMAIN if not on VPN).
- VPN clients on every platform with a single distribution artifact per user.
- New internal hostname = one A record in the private zone, ~30 seconds, no cert / client / config changes.

## What to monitor

- The DNS forwarder at `172.16.10.11` is a **single point of failure** for VPN-side name resolution. If that server goes down, VPN users can connect but can't resolve names. If uptime matters more than cost, the upgrade path is either (a) a second DNS forwarder VM as secondary with both IPs in the VNet DNS list, or (b) Azure DNS Private Resolver (managed, HA built in).
- Azure may rotate the gateway public IP during maintenance. If they do, every user has to re-import a fresh `.ovpn`. Use the runbook procedure to rebuild all `.ovpn` files at once.
- The wildcard cert `*.exepron.com` expires periodically — on renewal, install the new cert on **both** `172.16.1.4` and `172.16.10.11`.
- The root cert (`ExepronP2SRoot`) expires in 5 years from generation. See [ADMIN-RUNBOOK.md → Rotate the root certificate](ADMIN-RUNBOOK.md#rotate-the-root-certificate).
