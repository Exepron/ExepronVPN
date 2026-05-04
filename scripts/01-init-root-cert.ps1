# Generates the self-signed ROOT certificate that signs all VPN client certs.
# Run this once. After it completes:
#   1. Upload the resulting .base64.txt content to Azure VPN Gateway -> Point-to-site configuration -> Root certificates.
#   2. Run the elevated import command shown at the end to add the root to LocalMachine\Trusted Root.
#
# Microsoft's documented New-SelfSignedCertificate parameters are used here verbatim.

$repoRoot      = Split-Path -Parent $PSScriptRoot
$outFolder     = Join-Path $repoRoot "output"
$rootSubject   = "ExepronP2SRoot"
$validityYears = 5

if (-not (Test-Path $outFolder)) {
    New-Item -ItemType Directory -Force -Path $outFolder | Out-Null
}

# Wipe any prior Exepron VPN root + client certs from current user store
Write-Host "=== Cleanup of prior Exepron VPN certs in CurrentUser stores ==="
$myStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
$myStore.Open("ReadWrite")
$prior = @($myStore.Certificates | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" })
foreach ($c in $prior) {
    Write-Host "  Removing from My: $($c.Subject) [$($c.Thumbprint)]"
    $myStore.Remove($c)
}
$myStore.Close()
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$rootStore.Open("ReadWrite")
$prior = @($rootStore.Certificates | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" })
foreach ($c in $prior) {
    Write-Host "  Removing from Root: $($c.Subject) [$($c.Thumbprint)]"
    try { $rootStore.Remove($c) } catch { Write-Host "    (failed: $($_.Exception.Message))" }
}
$rootStore.Close()
Write-Host ""

Write-Host "=== Generating root cert ==="
$rootParams = @{
    Type              = 'Custom'
    Subject           = "CN=$rootSubject"
    KeySpec           = 'Signature'
    KeyExportPolicy   = 'Exportable'
    KeyUsage          = 'CertSign'
    KeyUsageProperty  = 'Sign'
    KeyLength         = 2048
    HashAlgorithm     = 'sha256'
    NotAfter          = (Get-Date).AddYears($validityYears)
    CertStoreLocation = 'Cert:\CurrentUser\My'
}
$rootCert = New-SelfSignedCertificate @rootParams
Write-Host "  Subject:    $($rootCert.Subject)"
Write-Host "  Thumbprint: $($rootCert.Thumbprint)"
Write-Host "  Expires:    $($rootCert.NotAfter)"
Write-Host ""

Write-Host "=== Adding to CurrentUser\Trusted Root CA ==="
$trustedStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$trustedStore.Open("ReadWrite")
$trustedStore.Add($rootCert)
$trustedStore.Close()
Write-Host "  Done"
Write-Host ""

Write-Host "=== Exporting root for Azure upload ==="
$cerPath    = Join-Path $outFolder "$rootSubject.cer"
$cerB64Path = Join-Path $outFolder "$rootSubject.base64.txt"
Export-Certificate -Cert $rootCert -FilePath $cerPath -Type CERT | Out-Null
[Convert]::ToBase64String($rootCert.RawData) | Out-File $cerB64Path -Encoding ASCII
Write-Host "  $cerPath"
Write-Host "  $cerB64Path"
Write-Host ""

Write-Host "=========================================================="
Write-Host "BASE64 root cert (paste into Azure VPN Gateway):"
Write-Host "=========================================================="
[Convert]::ToBase64String($rootCert.RawData)
Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host ""
Write-Host "  1. Azure portal -> Virtual network gateways -> ExepronVPN -> Point-to-site configuration"
Write-Host "     -> Root certificates -> add a new row:"
Write-Host "       Name: $rootSubject"
Write-Host "       Public certificate data: paste the base64 above"
Write-Host "     Save."
Write-Host ""
Write-Host "  2. Add the root to LocalMachine\Trusted Root (REQUIRED for Windows VPN client)."
Write-Host "     Open PowerShell as Administrator and run:"
Write-Host ""
Write-Host "       Import-Certificate -FilePath '$cerPath' -CertStoreLocation Cert:\LocalMachine\Root"
Write-Host ""
Write-Host "  3. Run scripts\02-issue-user-certs.ps1 to issue certs for each VPN user."
