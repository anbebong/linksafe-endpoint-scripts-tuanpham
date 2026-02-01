#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - Get System Certificates

.DESCRIPTION
    List all certificates in Windows Certificate Stores with details

.EXAMPLE
    .\Get-Certs.ps1
#>

# Set UTF-8 encoding for console output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Common Windows Certificate Stores
$CertStores = @(
    @{ StoreName = "Root"; StoreLocation = "LocalMachine"; Description = "Trusted Root Certification Authorities" },
    @{ StoreName = "CA"; StoreLocation = "LocalMachine"; Description = "Intermediate Certification Authorities" },
    @{ StoreName = "My"; StoreLocation = "LocalMachine"; Description = "Personal (Machine)" },
    @{ StoreName = "My"; StoreLocation = "CurrentUser"; Description = "Personal (User)" },
    @{ StoreName = "TrustedPeople"; StoreLocation = "LocalMachine"; Description = "Trusted People" },
    @{ StoreName = "TrustedPublisher"; StoreLocation = "LocalMachine"; Description = "Trusted Publishers" }
)

Write-Host "--- SYSTEM CERTIFICATES LIST ---" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan

$totalCount = 0

foreach ($store in $CertStores) {
    try {
        $storeName = $store.StoreName
        $storeLocation = $store.StoreLocation
        
        # Open certificate store
        $storeLocationEnum = [System.Security.Cryptography.X509Certificates.StoreLocation]::$storeLocation
        $certStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, $storeLocationEnum)
        $certStore.Open("ReadOnly")
        
        $certs = $certStore.Certificates
        
        if ($certs.Count -gt 0) {
            Write-Host ""
            Write-Host "Store: $($store.Description) ($storeLocation\$storeName)" -ForegroundColor Yellow
            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
            
            foreach ($cert in $certs) {
                $totalCount++
                
                # Extract certificate information
                $subject = $cert.Subject
                $issuer = $cert.Issuer
                $expiry = $cert.NotAfter
                $thumbprint = $cert.Thumbprint
                $friendlyName = if ($cert.FriendlyName) { $cert.FriendlyName } else { "N/A" }
                
                # Format expiry date
                $expiryStr = $expiry.ToString("yyyy-MM-dd HH:mm:ss")
                
                # Check if certificate is expiring soon (30 days)
                $daysUntilExpiry = ($expiry - (Get-Date)).Days
                $expiryStatus = if ($daysUntilExpiry -lt 0) {
                    "EXPIRED"
                } elseif ($daysUntilExpiry -lt 30) {
                    "EXPIRING SOON ($daysUntilExpiry days)"
                } else {
                    "Valid ($daysUntilExpiry days remaining)"
                }
                
                $expiryColor = if ($daysUntilExpiry -lt 0) {
                    "Red"
                } elseif ($daysUntilExpiry -lt 30) {
                    "Yellow"
                } else {
                    "Green"
                }
                
                Write-Host "Thumbprint: $thumbprint" -ForegroundColor White
                Write-Host "  - Name     : $friendlyName" -ForegroundColor Gray
                Write-Host "  - Subject  : $subject" -ForegroundColor Gray
                Write-Host "  - Issuer   : $issuer" -ForegroundColor Gray
                Write-Host "  - Expires  : $expiryStr" -ForegroundColor Gray
                Write-Host "  - Status   : " -NoNewline
                Write-Host $expiryStatus -ForegroundColor $expiryColor
                Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
            }
            
            $certStore.Close()
        }
    } catch {
        # Show warning if cannot access store
        if ($store.StoreLocation -eq "LocalMachine") {
            Write-Warning "Cannot access store: $($store.StoreLocation)\$($store.StoreName) - $_ (May require Administrator privileges)"
        } else {
            Write-Verbose "Cannot access store: $($store.StoreLocation)\$($store.StoreName) - $_"
        }
    }
}

Write-Host ""
Write-Host "Total certificates: $totalCount" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan

