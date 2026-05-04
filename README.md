# Exepron VPN

Admin tooling for the Exepron Azure Point-to-Site VPN — generates root + per-user certs, builds self-contained `.ovpn` files for distribution to Mac/iOS/Windows users via OpenVPN Connect.

## Repo layout

```
ExepronVPN/
├── README.md                     # this file
├── .gitignore                    # excludes .pfx, .key, .pem, .ovpn (sensitive)
├── docs/
│   ├── architecture-overview.md  # how the whole VPN + DNS stack fits together
│   ├── ADMIN-RUNBOOK.md          # day-to-day ops: onboard user, revoke, rotate root
│   └── MAC-IOS-SETUP.md          # end-user instructions to send each user
├── scripts/
│   ├── 01-init-root-cert.ps1     # generate the self-signed root cert (run once)
│   ├── 02-issue-user-certs.ps1   # issue per-user client certs (signed by root)
│   ├── 03-build-ovpn-files.ps1   # build self-contained .ovpn files per user
│   └── troubleshooting/
│       ├── inspect-cert-chain.ps1
│       └── cleanup-cert-stores.ps1
├── templates/
│   └── vpnconfig.ovpn            # Azure-generated OpenVPN profile template (no private keys)
└── output/                       # generated certs and .ovpn files (gitignored)
```

## Quick start (first time setting up)

### 0. Prerequisites

- Windows 10/11 with PowerShell 5.1+.
- Access to Azure Portal for the VPN gateway resource.
- An up-to-date `templates/vpnconfig.ovpn` (download from Azure VPN client zip if missing — see [refresh template](docs/ADMIN-RUNBOOK.md#refresh-the-openvpn-template)).

### 1. Generate the root cert

```
powershell -ExecutionPolicy Bypass -File scripts\01-init-root-cert.ps1
```

The script:
- Wipes any prior `Exepron*` certs from your CurrentUser stores
- Creates `ExepronP2SRoot` (self-signed, 5-year validity) in `Cert:\CurrentUser\My`
- Adds it to `Cert:\CurrentUser\Root`
- Exports `output\ExepronP2SRoot.cer` and `output\ExepronP2SRoot.base64.txt`

After it runs:

1. **Upload to Azure**: Portal → Virtual network gateways → ExepronVPN → Point-to-site configuration → Root certificates → add a new row named `ExepronP2SRoot`, paste the base64 from `output\ExepronP2SRoot.base64.txt`. Save.
2. **Add to LocalMachine\Trusted Root** (admin PowerShell):
   ```
   Import-Certificate -FilePath "output\ExepronP2SRoot.cer" -CertStoreLocation Cert:\LocalMachine\Root
   ```

### 2. Issue user certs

Edit the `$users` array near the top of `scripts\02-issue-user-certs.ps1` to match your team. Then:

```
powershell -ExecutionPolicy Bypass -File scripts\02-issue-user-certs.ps1
```

Produces `output\ExepronP2SChild_<UserName>.pfx` and `.cer` for each user.

### 3. Build per-user .ovpn files

Make sure the same `$users` array is in `scripts\03-build-ovpn-files.ps1`. Then:

```
powershell -ExecutionPolicy Bypass -File scripts\03-build-ovpn-files.ps1
```

Produces `output\ExepronVPN_<UserName>.ovpn` — one self-contained profile per user.

### 4. Distribute

For each user, send:

- `output\ExepronVPN_<UserName>.ovpn`
- `docs\MAC-IOS-SETUP.md`

That's all they need. The `.ovpn` is self-contained — no separate cert install, no password to share. Send via secure channel (1Password, Signal, USB) — not email.

## Recurring tasks

See [docs/ADMIN-RUNBOOK.md](docs/ADMIN-RUNBOOK.md) for:

- Onboarding new users
- Re-issuing expired or compromised certs
- Revoking a user's access
- Rotating the root cert (every ~5 years)
- Refreshing the OpenVPN template after Azure-side changes

## Architecture

See [docs/architecture-overview.md](docs/architecture-overview.md) for the full picture — how the public/private DNS zones, VPN gateway, DNS forwarder, wildcard SSL cert, and client connections all fit together.

## Security notes

- **Never commit** `.pfx`, `.cer` (client cert), `.key`, `.pem`, or `.ovpn` files. The `.gitignore` excludes them, but double-check before pushing to a remote.
- **The `output/` folder is gitignored**. Treat anything inside it as secret.
- **The PFX password** (`Exepron2026` by default) is hardcoded in `02-issue-user-certs.ps1` for convenience — change it before generating real production certs, and share via a password manager only.
- **The root cert's private key** lives in your CurrentUser cert store. If your machine is lost or compromised, [rotate the root](docs/ADMIN-RUNBOOK.md#rotate-the-root-certificate) — every user will need a new `.ovpn`.
- **This repo is safe to push to a private remote**. Do NOT push to a public one — even though secrets are gitignored, the architectural detail and naming conventions reduce the security margin you'd want for a public posture.

## Troubleshooting

If something looks wrong with the local cert state, run:

```
powershell -ExecutionPolicy Bypass -File scripts\troubleshooting\inspect-cert-chain.ps1
```

Or to wipe and start over:

```
powershell -ExecutionPolicy Bypass -File scripts\troubleshooting\cleanup-cert-stores.ps1
```

The latter prints an admin command to remove `LocalMachine` entries (those need elevation).

For `.ovpn` issues on user devices, see the **Common issues** section of [docs/MAC-IOS-SETUP.md](docs/MAC-IOS-SETUP.md).
