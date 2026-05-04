# Issues client certificates for each VPN user, signed by ExepronP2SRoot.
# Edit the $users array below to match the people you want to onboard.
# Run after 01-init-root-cert.ps1 has created the root.

$repoRoot     = Split-Path -Parent $PSScriptRoot
$outFolder    = Join-Path $repoRoot "output"
$rootSubject  = "ExepronP2SRoot"
$pfxPassword  = "Exepron2026"   # CHANGE THIS - hardcoded default for convenience only
$validYears   = 2

# Add or remove users here.
$users = @(
    "Ofer",
    "Johnt",
    "Toni"
)

if (-not (Test-Path $outFolder)) {
    New-Item -ItemType Directory -Force -Path $outFolder | Out-Null
}

# Find root cert (must already exist in CurrentUser\My with private key)
$rootCert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=$rootSubject" } | Select-Object -First 1
if (-not $rootCert) {
    Write-Host "ERROR: Root cert '$rootSubject' not found in CurrentUser\My."
    Write-Host "Run scripts\01-init-root-cert.ps1 first."
    exit 1
}
if (-not $rootCert.HasPrivateKey) {
    Write-Host "ERROR: Root cert has no private key — cannot sign new client certs."
    exit 1
}
Write-Host "Found root: $($rootCert.Subject) [$($rootCert.Thumbprint)]"
Write-Host ""

$pwd = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText

foreach ($user in $users) {
    $clientSubject = "ExepronP2SChild_$user"
    Write-Host "=== Issuing cert for $user ==="

    # Microsoft's documented client cert parameters
    $clientParams = @{
        Type              = 'Custom'
        Subject           = "CN=$clientSubject"
        DnsName           = $clientSubject
        KeySpec           = 'Signature'
        KeyExportPolicy   = 'Exportable'
        KeyLength         = 2048
        HashAlgorithm     = 'sha256'
        NotAfter          = (Get-Date).AddYears($validYears)
        CertStoreLocation = 'Cert:\CurrentUser\My'
        Signer            = $rootCert
        TextExtension     = @('2.5.29.37={text}1.3.6.1.5.5.7.3.2')   # Client Authentication EKU
    }
    $cert = New-SelfSignedCertificate @clientParams
    Write-Host "  Subject:    $($cert.Subject)"
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  Expires:    $($cert.NotAfter)"

    $pfxPath = Join-Path $outFolder "$clientSubject.pfx"
    $cerPath = Join-Path $outFolder "$clientSubject.cer"
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pwd -ChainOption BuildChain | Out-Null
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
    Write-Host "  PFX: $pfxPath"
    Write-Host "  CER: $cerPath"

    # Remove the cert from admin's Personal store (the PFX is the backup)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
    $store.Open("ReadWrite")
    $store.Remove($cert)
    $store.Close()
    Write-Host "  Removed from admin Personal store"
    Write-Host ""
}

Write-Host "=== Final state ==="
Write-Host "Personal store (should have only the root):"
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -match "ExepronP2S" } | Format-Table Subject, HasPrivateKey, NotAfter, Thumbprint -AutoSize

Write-Host "Files generated:"
Get-ChildItem $outFolder -Filter "ExepronP2SChild_*.pfx" | Format-Table Name, Length, LastWriteTime -AutoSize

Write-Host "PFX password (used for all PFX files): $pfxPassword"
Write-Host ""
Write-Host "NEXT STEP: Run scripts\03-build-ovpn-files.ps1 to bake each user's cert into a .ovpn for distribution."
