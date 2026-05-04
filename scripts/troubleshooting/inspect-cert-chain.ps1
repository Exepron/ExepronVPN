# Diagnose cert chain issues. Shows what's in your stores and whether the chain validates.

function Show-CertDetails($cert, $label) {
    Write-Host "=== $label ==="
    Write-Host "Subject:           $($cert.Subject)"
    Write-Host "Issuer:            $($cert.Issuer)"
    Write-Host "Thumbprint:        $($cert.Thumbprint)"
    Write-Host "Has private key:   $($cert.HasPrivateKey)"
    Write-Host "Not before:        $($cert.NotBefore)"
    Write-Host "Not after:         $($cert.NotAfter)"
    Write-Host ""
    Write-Host "Enhanced Key Usages:"
    if ($cert.EnhancedKeyUsageList.Count -eq 0) {
        Write-Host "  (none, cert is usable for any purpose)"
    } else {
        foreach ($eku in $cert.EnhancedKeyUsageList) {
            Write-Host "  $($eku.FriendlyName)  ($($eku.ObjectId))"
        }
    }
    Write-Host ""
    Write-Host "Extensions:"
    foreach ($ext in $cert.Extensions) {
        $oidName = if ($ext.Oid.FriendlyName) { $ext.Oid.FriendlyName } else { "(unnamed)" }
        Write-Host "  [$($ext.Oid.Value)] $oidName  Critical=$($ext.Critical)"
    }
    Write-Host ""
}

Write-Host "===== CurrentUser\My ====="
$myExepron = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" }
foreach ($c in $myExepron) { Show-CertDetails $c "CurrentUser\My" }

Write-Host "===== CurrentUser\Trusted Root CA (Exepron only) ====="
$rootExepron = Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" }
foreach ($c in $rootExepron) { Show-CertDetails $c "CurrentUser\Root" }

Write-Host "===== LocalMachine\Trusted Root CA (Exepron only) ====="
$lmExepron = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match "ExepronP2S|ExepronVPN" }
foreach ($c in $lmExepron) { Show-CertDetails $c "LocalMachine\Root" }

Write-Host "===== Chain build for client cert ====="
$client = $myExepron | Where-Object { $_.Subject -like "*Child*" -or $_.Subject -like "*Client*" } | Select-Object -First 1
if ($client) {
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chainBuilt = $chain.Build($client)
    Write-Host "Chain build success: $chainBuilt"
    foreach ($e in $chain.ChainElements) {
        Write-Host "  - $($e.Certificate.Subject)"
    }
    foreach ($s in $chain.ChainStatus) {
        Write-Host "  status: $($s.Status): $($s.StatusInformation)"
    }
} else {
    Write-Host "No client cert found in CurrentUser\My."
}
