$hostsFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"
# Specify the hostname and IP address
$hostname = "example.com"
$ipAddress = "192.168.1.10"
# Check if the hosts file exists
if (Test-Path $hostsFilePath) {
    # Check if the entry already exists in the hosts file
    $existingEntry = Get-Content $hostsFilePath | Where-Object { $_ -like "$ipAddress *$hostname*" }
    if ($existingEntry) {
        Write-Host "Entry already exists in the hosts file."
    }
    else {
        # Append the new entry to the hosts file
        $newEntry = "$ipAddress $hostname"
        Add-Content -Path $hostsFilePath -Value $newEntry
        Write-Host "Entry added to the hosts file."
    }
}
else {
    Write-Host "Hosts file not found."
}