# Admin runbook — Exepron VPN

How to do recurring admin tasks. For the one-time architecture and setup history, see `architecture-overview.md` and `private-dns-vpn-setup.md`.

## Common tasks

- [Onboard a new VPN user](#onboard-a-new-vpn-user)
- [Re-issue a user's cert (rotation, leak, lost device)](#re-issue-a-users-cert)
- [Revoke a user's access](#revoke-a-users-access)
- [Rotate the root certificate (every ~5 years)](#rotate-the-root-certificate)
- [Refresh the OpenVPN template after gateway changes](#refresh-the-openvpn-template)

---

## Onboard a new VPN user

1. Open `scripts\02-issue-user-certs.ps1` and add the user's name to the `$users` array, e.g.:
   ```powershell
   $users = @("Ofer", "Johnt", "Toni", "NewPerson")
   ```
2. Open `scripts\03-build-ovpn-files.ps1` and add the same name to its `$users` array.
3. Run the issue script:
   ```
   powershell -ExecutionPolicy Bypass -File scripts\02-issue-user-certs.ps1
   ```
   This creates `output\ExepronP2SChild_NewPerson.pfx` and `.cer`.

   **Note:** Re-running this on existing users creates *additional* certs for them rather than replacing the old ones. If you only want to add the new person, comment out or remove the existing names from the array temporarily, or just accept the extra certs (they're harmless — just extra `.pfx` files).
4. Run the .ovpn builder:
   ```
   powershell -ExecutionPolicy Bypass -File scripts\03-build-ovpn-files.ps1
   ```
   This creates `output\ExepronVPN_NewPerson.ovpn`.
5. Send the new user:
   - `output\ExepronVPN_NewPerson.ovpn`
   - `docs\MAC-IOS-SETUP.md`

   Use a secure channel (1Password, Signal, in-person USB) — not email.
6. Commit the user list change to git:
   ```
   git add scripts\02-issue-user-certs.ps1 scripts\03-build-ovpn-files.ps1
   git commit -m "Add VPN user: NewPerson"
   ```
   The output files stay out of git (gitignored).

## Re-issue a user's cert

Reasons: cert is approaching expiry (the script issues 2-year certs), user lost a device, you suspect the `.ovpn` was leaked.

1. Open `scripts\02-issue-user-certs.ps1`.
2. Comment out everyone except the user being re-issued:
   ```powershell
   $users = @(
       # "Ofer",
       "Johnt"
       # "Toni"
   )
   ```
3. Run the script. New `ExepronP2SChild_Johnt.pfx` overwrites the old one.
4. Run `03-build-ovpn-files.ps1` (still with just Johnt active).
5. Send the new `.ovpn` to Johnt.
6. **Revoke the old cert** — see [Revoke a user's access](#revoke-a-users-access).
7. Restore the full `$users` array in both scripts before committing.

## Revoke a user's access

When someone leaves or a cert is compromised:

1. **Find the cert thumbprint** to revoke.
   ```
   powershell -ExecutionPolicy Bypass -File scripts\troubleshooting\inspect-cert-chain.ps1
   ```
   Or open the `.cer` file in `output\` and read its thumbprint from the Details tab.
2. **Add to revocation list on Azure**:
   - Azure Portal → Virtual network gateways → ExepronVPN → Point-to-site configuration → **Revoked certificates**.
   - Click **+ Add revoked certificate**:
     - Name: `Revoked-<UserName>-<YYYYMMDD>`
     - Thumbprint: the thumbprint from step 1 (no spaces, uppercase)
   - **Save**. Wait 1 minute.
3. The user can no longer connect even if they still have the `.ovpn` file.
4. (Optional) Delete the user's local `.pfx` and `.ovpn` from `output\` if they're definitely not coming back.

## Rotate the root certificate

Do this when:
- The root is approaching expiry (5-year validity by default).
- You suspect the root's private key has been compromised.

This is **disruptive** — every user has to re-import a new `.ovpn`. Plan a maintenance window.

1. Run `scripts\01-init-root-cert.ps1`. This wipes the old root from the local store and creates a fresh one.
2. Add the new root to Azure (Point-to-site configuration → Root certificates → add row → paste base64 from `output\ExepronP2SRoot.base64.txt` → Save).
3. Add the new root to LocalMachine\Trusted Root (admin PowerShell):
   ```
   Import-Certificate -FilePath "output\ExepronP2SRoot.cer" -CertStoreLocation Cert:\LocalMachine\Root
   ```
4. **Optional — also remove the OLD root from Azure** if no users are still using certs signed by it. If any old certs are still valid and you want them to keep working, leave the old root registered in parallel.
5. Re-issue every user's cert: run `scripts\02-issue-user-certs.ps1` with the full `$users` list.
6. Build new .ovpn files: run `scripts\03-build-ovpn-files.ps1`.
7. Distribute the new `.ovpn` to every user. They re-import.

## Refresh the OpenVPN template

If the Azure VPN gateway has been migrated, IP-changed, or otherwise modified, the embedded VPN server FQDN/TLS settings in `templates\vpnconfig.ovpn` may be stale.

1. Azure Portal → Virtual network gateways → ExepronVPN → Point-to-site configuration → **Download VPN client**.
2. Save zip → extract.
3. Copy the extracted `OpenVPN\vpnconfig.ovpn` over `templates\vpnconfig.ovpn` in this repo.
4. Re-run `scripts\03-build-ovpn-files.ps1` to rebuild every user's `.ovpn` from the new template.
5. Distribute the new `.ovpn` files to every user.

If the template's `remote` line FQDN didn't change, refreshing isn't strictly necessary. Use this when the gateway has been touched.

---

## Notes on security

- `.pfx` files in `output\` and on your machine are encrypted with the password in `02-issue-user-certs.ps1`. The default password (`Exepron2026`) is in plaintext in the repo — that's deliberate, since the .pfx files themselves are gitignored. **The repo is safe to push to a private remote, but never to a public one.**
- For higher-security needs, change the password to something stronger and unique per user, share via a password manager, and rotate when staff change.
- The root's private key (`ExepronP2SRoot` in your CurrentUser\My) is the most sensitive thing on this machine. If your laptop is lost or compromised, [rotate the root cert](#rotate-the-root-certificate).
