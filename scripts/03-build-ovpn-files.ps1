# Builds per-user .ovpn files (cert + private key embedded inline as PEM).
# Output is one .ovpn file per user, ready to send to that user.
# Each user only needs their .ovpn file plus the docs\MAC-IOS-SETUP.md instructions.
#
# Prerequisites:
#   - Per-user .pfx files exist in output\ (from 02-issue-user-certs.ps1)
#   - templates\vpnconfig.ovpn exists (the Azure-generated OpenVPN profile template)
#
# To get the template:
#   Azure portal -> ExepronVPN -> Point-to-site configuration -> Download VPN client.
#   Extract the zip, then copy OpenVPN\vpnconfig.ovpn into this repo's templates\ folder.

$repoRoot     = Split-Path -Parent $PSScriptRoot
$outFolder    = Join-Path $repoRoot "output"
$ovpnTemplate = Join-Path $repoRoot "templates\vpnconfig.ovpn"
$pfxPassword  = "Exepron2026"

$users = @(
    "Ofer",
    "Johnt",
    "Toni"
)

if (-not (Test-Path $ovpnTemplate)) {
    Write-Host "ERROR: OpenVPN template not found at $ovpnTemplate"
    Write-Host ""
    Write-Host "To get it:"
    Write-Host "  1. Azure portal -> ExepronVPN -> Point-to-site configuration -> Download VPN client."
    Write-Host "  2. Extract the zip."
    Write-Host "  3. Copy OpenVPN\vpnconfig.ovpn into this repo's templates\ folder."
    exit 1
}

# C# helper compiled at runtime. PowerShell's array unrolling doesn't apply to .NET method calls,
# so this works on Windows PowerShell 5.1 even though we don't have ExportPkcs8PrivateKey.
$csharp = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

public static class ExepronCertExport
{
    public static string ExportCertPem(X509Certificate2 cert)
    {
        string b64 = Convert.ToBase64String(cert.RawData, Base64FormattingOptions.InsertLineBreaks);
        return "-----BEGIN CERTIFICATE-----\r\n" + b64 + "\r\n-----END CERTIFICATE-----";
    }

    public static string ExportRsaPrivateKeyPem(X509Certificate2 cert)
    {
        RSA rsa = cert.GetRSAPrivateKey();
        if (rsa == null) { throw new InvalidOperationException("No RSA private key on cert"); }
        RSAParameters p = rsa.ExportParameters(true);

        byte[] der = EncodeRsaPrivateKey(p);
        string b64 = Convert.ToBase64String(der, Base64FormattingOptions.InsertLineBreaks);
        return "-----BEGIN RSA PRIVATE KEY-----\r\n" + b64 + "\r\n-----END RSA PRIVATE KEY-----";
    }

    private static byte[] EncodeRsaPrivateKey(RSAParameters p)
    {
        // PKCS#1 RSAPrivateKey ASN.1:
        // SEQUENCE { INTEGER version, INTEGER modulus, INTEGER publicExponent,
        //            INTEGER privateExponent, INTEGER prime1, INTEGER prime2,
        //            INTEGER exponent1, INTEGER exponent2, INTEGER coefficient }
        using (MemoryStream body = new MemoryStream())
        {
            EncodeInteger(body, new byte[] { 0 });
            EncodeInteger(body, p.Modulus);
            EncodeInteger(body, p.Exponent);
            EncodeInteger(body, p.D);
            EncodeInteger(body, p.P);
            EncodeInteger(body, p.Q);
            EncodeInteger(body, p.DP);
            EncodeInteger(body, p.DQ);
            EncodeInteger(body, p.InverseQ);
            return EncodeSequence(body.ToArray());
        }
    }

    private static void EncodeInteger(MemoryStream stream, byte[] bytes)
    {
        List<byte> trimmed = new List<byte>(bytes);
        while (trimmed.Count > 1 && trimmed[0] == 0) { trimmed.RemoveAt(0); }
        if ((trimmed[0] & 0x80) != 0) { trimmed.Insert(0, 0); }

        stream.WriteByte(0x02);
        WriteLength(stream, trimmed.Count);
        foreach (byte b in trimmed) { stream.WriteByte(b); }
    }

    private static byte[] EncodeSequence(byte[] content)
    {
        using (MemoryStream ms = new MemoryStream())
        {
            ms.WriteByte(0x30);
            WriteLength(ms, content.Length);
            ms.Write(content, 0, content.Length);
            return ms.ToArray();
        }
    }

    private static void WriteLength(MemoryStream stream, int n)
    {
        if (n < 128)
        {
            stream.WriteByte((byte)n);
        }
        else
        {
            List<byte> bytes = new List<byte>();
            int x = n;
            while (x > 0) { bytes.Insert(0, (byte)(x & 0xFF)); x >>= 8; }
            stream.WriteByte((byte)(0x80 | bytes.Count));
            foreach (byte b in bytes) { stream.WriteByte(b); }
        }
    }
}
"@

if (-not ("ExepronCertExport" -as [type])) {
    Add-Type -TypeDefinition $csharp -Language CSharp
}

$tplContent = Get-Content $ovpnTemplate -Raw

foreach ($user in $users) {
    $pfxPath = Join-Path $outFolder "ExepronP2SChild_$user.pfx"
    if (-not (Test-Path $pfxPath)) {
        Write-Host "SKIP $user - PFX not found: $pfxPath"
        continue
    }

    Write-Host "=== Building .ovpn for $user ==="
    $pfxBytes = [System.IO.File]::ReadAllBytes($pfxPath)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 `
        -ArgumentList $pfxBytes, $pfxPassword, ([System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    $certPem = [ExepronCertExport]::ExportCertPem($cert)
    $keyPem  = [ExepronCertExport]::ExportRsaPrivateKeyPem($cert)

    $ovpn = $tplContent
    $ovpn = $ovpn -replace '\$CLIENTCERTIFICATE', $certPem
    $ovpn = $ovpn -replace '\$PRIVATEKEY', $keyPem

    # Strip directives that OpenVPN Connect 3.x (iOS/Android) rejects.
    # Azure-generated templates sometimes ship these uncommented despite their own comment
    # warning OpenVPN Connect 3.x users to comment them out.
    $ovpn = $ovpn -replace '(?m)^\s*log\s+\S+\s*$', '#log (stripped for OpenVPN Connect 3.x compatibility)'
    $ovpn = $ovpn -replace '(?m)^\s*log-append\s+\S+\s*$', '#log-append (stripped)'

    $outPath = Join-Path $outFolder "ExepronVPN_$user.ovpn"
    Set-Content -Path $outPath -Value $ovpn -Encoding ASCII -NoNewline

    # Sanity check - look for BEGIN/END markers AND verify base64 chunk length
    $check = Get-Content $outPath -Raw
    $issues = @()
    if ($check -match '\$CLIENTCERTIFICATE')      { $issues += '$CLIENTCERTIFICATE not replaced' }
    if ($check -match '\$PRIVATEKEY')             { $issues += '$PRIVATEKEY not replaced' }
    if ($check -notmatch 'BEGIN CERTIFICATE')      { $issues += 'cert PEM missing' }
    if ($check -notmatch 'BEGIN RSA PRIVATE KEY')  { $issues += 'key PEM missing' }
    if ($issues.Count -gt 0) {
        Write-Host "  WARNING: $($issues -join ', ')"
    } else {
        $size = (Get-Item $outPath).Length
        Write-Host "  OK -> $outPath ($size bytes)"
    }
}

Write-Host ""
Write-Host "=== Files in output\ ==="
Get-ChildItem $outFolder -Filter "*.ovpn" | Format-Table Name, Length, LastWriteTime -AutoSize

Write-Host ""
Write-Host "Distribute one .ovpn file + docs\MAC-IOS-SETUP.md to each user."
Write-Host "DO NOT send the .pfx, .cer, or password - those are baked into the .ovpn."
