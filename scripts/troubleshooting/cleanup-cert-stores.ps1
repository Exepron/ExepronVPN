# Removes all Exepron VPN-related certs from CurrentUser stores.
# LocalMachine\Root requires admin elevation - prints the command to run separately.
# Use this when you want to start over from scratch.

Write-Host "=== Removing from CurrentUser\My ==="
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
$store.Open("ReadWrite")
$found = @($store.Certificates | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" })
foreach ($c in $found) {
    Write-Host "  Removing $($c.Subject) [$($c.Thumbprint)]"
    $store.Remove($c)
}
$store.Close()
if ($found.Count -eq 0) { Write-Host "  (nothing to remove)" }
Write-Host ""

Write-Host "=== Removing from CurrentUser\Root ==="
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$store.Open("ReadWrite")
$found = @($store.Certificates | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" })
foreach ($c in $found) {
    Write-Host "  Removing $($c.Subject) [$($c.Thumbprint)]"
    try { $store.Remove($c) } catch { Write-Host "    (failed: $($_.Exception.Message))" }
}
$store.Close()
if ($found.Count -eq 0) { Write-Host "  (nothing to remove)" }
Write-Host ""

Write-Host "=== LocalMachine\Root - check ==="
$lm = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" }
if ($lm.Count -gt 0) {
    Write-Host "Found Exepron entries in LocalMachine\Root that need elevated removal:"
    foreach ($c in $lm) { Write-Host "  $($c.Subject) [$($c.Thumbprint)]" }
    Write-Host ""
    Write-Host "Run this in an ADMIN PowerShell to remove them:"
    Write-Host ""
    Write-Host '  Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" } | ForEach-Object { Remove-Item -Path $_.PSPath -Force }'
} else {
    Write-Host "  (no Exepron entries found in LocalMachine\Root)"
}
