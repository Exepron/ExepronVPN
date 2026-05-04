# Exepron VPN setup for macOS and iOS

This is a one-time setup, ~5 minutes, on a brand-new Mac or iPhone/iPad. You don't need to install or remove anything beforehand — these instructions assume nothing is currently installed.

## What you should have received

A single file from the admin:

- **`ExepronVPN_<YourName>.ovpn`** — for example, `ExepronVPN_Johnt.ovpn` or `ExepronVPN_Toni.ovpn`. It contains everything: the VPN server address, your personal certificate, and your private key. Treat it like a password.

That's it — no separate cert files, no `.pfx`, no password to type. Everything is bundled into the `.ovpn`.

If you have multiple devices (e.g. MacBook + iPhone), the same `.ovpn` file works on both. You can just copy it.

## Important security note

The `.ovpn` file contains your private key. Anyone who has the file can connect to the company network as you. Treat it accordingly:

- Don't email it to others or post it in shared chat channels.
- After you've imported it on each of your devices, optionally delete the `.ovpn` file from your Downloads folder (it's already loaded into the OpenVPN app at that point).
- If you lose the file or a device, tell the admin so they can revoke that specific certificate.

---

## macOS setup

These steps work on macOS 12 (Monterey) or newer.

### 1. Install the OpenVPN Connect app

- Open the **Mac App Store** (Cmd+Space, type "App Store", Enter).
- Search for **OpenVPN Connect** (publisher: OpenVPN Inc.).
- Click **Get** / **Install**. It's free.
- Wait for the install to finish.

### 2. Get the `.ovpn` file onto the Mac

The admin sent you `ExepronVPN_<YourName>.ovpn`. However it arrived (email attachment, AirDrop, USB drive), get it onto the Mac and remember where you saved it. Downloads folder is fine.

### 3. Import into OpenVPN Connect

- Open the **OpenVPN Connect** app (in Applications).
- The first time you launch it, it shows an agreement — accept.
- Click **Import Profile** (or the **+** button).
- Choose **File** (not URL).
- Drag your `.ovpn` file into the window, or click **Browse** and pick it.
- Click **Connect** when prompted to add the profile, or **Save** to add it without connecting.
- macOS will ask to "Allow OpenVPN Connect to add VPN configurations" — click **Allow**, enter your Mac password.

### 4. Connect

- The profile now appears in OpenVPN Connect's main screen.
- Click the toggle / **Connect** button.
- After a few seconds, the status should show **CONNECTED**.

### 5. Verify

Open Safari or Chrome and go to:

```
https://sales.exepron.com
```

The page should load with no certificate warning.

If you want to confirm via Terminal:

```
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
nslookup sales.exepron.com
```

The expected answer is `Address: 172.16.1.4` from server `172.16.10.11`. If you see something else (or "can't find"), the VPN isn't fully up — try disconnect and reconnect once.

### 6. Disconnect / reconnect later

When you're done, hit the toggle in OpenVPN Connect to disconnect. Reconnect by toggling again — no reimport needed.

---

## iOS / iPadOS setup

### 1. Install the OpenVPN Connect app

- Open the **App Store** on the device.
- Search for **OpenVPN Connect** (publisher: OpenVPN Inc.).
- Tap **Get**. It's free.

### 2. Get the `.ovpn` file onto the device

Easiest options:

- **AirDrop** from a Mac that has the file.
- **Email** the file to yourself as an attachment — open the email on the device.
- **iCloud Drive / OneDrive / Files app** — drop the file in cloud storage, open it on the device.

### 3. Open the file in OpenVPN Connect

- Tap the `.ovpn` file (in Mail, Files, AirDrop notification, etc.).
- iOS asks how to open it → choose **OpenVPN** (or **Open in OpenVPN**).
- The OpenVPN Connect app opens, showing an "Import Profile" screen with your profile preloaded.
- Tap **ADD** at the top-right.

### 4. Allow VPN access

- iOS prompts: "OpenVPN would like to add VPN Configurations" → tap **Allow**.
- Enter your device passcode.

### 5. Connect

- In OpenVPN Connect, tap the toggle next to your profile to connect.
- After a few seconds, status shows **CONNECTED** and a small **VPN** badge appears at the top of the screen.

### 6. Verify

Open Safari and go to:

```
https://sales.exepron.com
```

Page should load.

### 7. Disconnect / reconnect later

Same toggle — flip it off to disconnect, on to reconnect. No reimport needed.

---

## Common issues

| Problem | Likely cause | Fix |
|---|---|---|
| OpenVPN Connect says "AUTH_FAILED" | The `.ovpn` was edited or corrupted in transit | Get a fresh copy from the admin |
| Connects but websites don't load | Wi-Fi/captive portal sign-in incomplete | Disconnect, sign into Wi-Fi normally first, reconnect VPN |
| `sales.exepron.com` doesn't resolve | DNS not getting pushed (rare; usually a transient network issue) | Disconnect, reconnect; if persistent, contact admin |
| "Connection failed: TLS handshake error" | Server temporarily unreachable | Wait 30 seconds, retry; if persistent, contact admin |
| iOS won't open the .ovpn in OpenVPN | Filename was renamed and lost the `.ovpn` extension | Rename to end in `.ovpn` or have admin send a new copy |
| Mac says "App is from unidentified developer" | Wrong app downloaded | Use the official Mac App Store, publisher must be **OpenVPN Inc.** |

If your issue isn't here, send the admin a screenshot of the error plus your OS version (Mac: Apple menu → About This Mac; iOS: Settings → General → About → Software Version).

---

## What this is actually doing (one paragraph)

When you connect, the OpenVPN client uses the certificate inside your `.ovpn` to authenticate to Azure's VPN server. Azure recognizes your certificate (issued by `ExepronP2SRoot`, which is registered as a trusted root on the Azure gateway), gives your device a private IP inside the Exepron internal network, and routes traffic to internal hostnames (`sales.exepron.com`, `admin.exepron.com`, `salestest.exepron.com`, `admintest.exepron.com`) through the encrypted tunnel. All other internet traffic continues to use your normal connection — only company-internal addresses are tunneled. When you disconnect, your device is back to normal internet usage.

## How to remove the VPN later

If you ever stop working with Exepron and want to clean up:

- **macOS**: open OpenVPN Connect, click the profile, delete it. Optionally uninstall the app via Launchpad → press-and-hold the icon → X.
- **iOS**: open OpenVPN Connect, swipe left on the profile, tap Delete. Optionally also delete in Settings → General → VPN & Device Management → tap the VPN config → Delete VPN.

That's it — there's no leftover certificate to remove because everything was inside the `.ovpn`.
