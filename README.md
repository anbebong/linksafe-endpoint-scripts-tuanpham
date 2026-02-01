# LINKSAFE Patch Management Scripts

Standalone patch management scripts for Linux and Windows systems. Outputs JSON for integration with monitoring systems (NetXMS, Wazuh, etc.).

## Features

- **Multi-OS Support**: Debian/Ubuntu (APT), RHEL/CentOS/Rocky (DNF/YUM), SUSE (Zypper), Windows
- **JSON Output**: All scripts output structured JSON for easy parsing
- **Hook System**: Pre-upgrade, pre-reboot, and post-upgrade hooks
- **Standalone**: No external dependencies beyond system package managers
- **Security-First**: Option to install security updates only

## Directory Structure

```
linksafe-patch-scripts/
├── lib/                      # Common libraries
│   ├── common.sh             # Logging, JSON helpers, state management
│   ├── os-detect.sh          # OS and package manager detection
│   └── hooks-runner.sh       # Hook execution framework
├── linux/
│   ├── lib/                  # Package manager libraries
│   │   ├── apt.sh            # APT (Debian/Ubuntu)
│   │   ├── dnf.sh            # DNF/YUM (RHEL/CentOS/Rocky)
│   │   └── zypper.sh         # Zypper (SUSE)
│   ├── actions/              # Action scripts
│   │   ├── check-updates.sh  # List available updates
│   │   ├── install-updates.sh# Install updates
│   │   ├── check-reboot.sh   # Check reboot status
│   │   ├── install-security.sh # Security updates only
│   │   ├── list-installed.sh # List installed packages
│   │   ├── rollback.sh       # Rollback support
|   |   ├── setup-proxy.sh    # Install proxy
|   |   ├── sync-hosts.sh     # Sync hosts
|   |   ├── update-certs.sh   # Update certs
|   |   └── firewall-rules.sh # Install iptables rule
│   └── hooks.d/              # Hook scripts
│       ├── pre-upgrade/
│       ├── pre-reboot/
│       └── post-upgrade/
├── windows/
│   ├── lib/
│   │   └── WindowsUpdate.psm1 # Windows Update API module
│   ├── actions/
│   │   ├── Check-Updates.ps1
│   │   ├── Install-Updates.ps1
│   │   ├── Check-Reboot.ps1
│   │   ├── Get-InstalledKB.ps1
│   │   ├── Install-SecurityUpdates.ps1
|   |   ├── Setup-Proxy.ps1
|   |   ├── Setup-DNS.ps1
|   |   ├── Update-Certs.ps1
|   |   └── Firewall-Rules.ps1
│   └── hooks.d/
│       ├── pre-upgrade/
│       ├── pre-reboot/
│       └── post-upgrade/
├── tests/
│   ├── test-linux.sh
│   └── Test-Windows.ps1
└── install.sh
```

## Quick Start

### Linux

```bash
# Install
sudo ./install.sh

# Check for updates
sudo linksafe-check-updates

# Install security updates only
sudo linksafe-install-updates --security

# Install all updates
sudo linksafe-install-updates --all

# Check if reboot required
linksafe-check-reboot
```

### Windows (PowerShell as Administrator)

```powershell
# Check for updates
.\windows\actions\Check-Updates.ps1

# Install security updates
.\windows\actions\Install-SecurityUpdates.ps1

# Install all updates with reboot
.\windows\actions\Install-Updates.ps1 -Reboot

# Check reboot status
.\windows\actions\Check-Reboot.ps1
```

## Action Scripts

### check-updates (Linux) / Check-Updates.ps1 (Windows)

List available updates.

```bash
# Linux
./check-updates.sh [--security-only] [--refresh] [--save]

# Windows PowerShell
.\Check-Updates.ps1 [-SecurityOnly] [-Quiet]
```

**Output:**
```json
{
  "hostname": "server01",
  "timestamp": "2024-01-15T10:30:00Z",
  "os_family": "debian",
  "pkg_manager": "apt",
  "total_updates": 15,
  "security_updates": 3,
  "updates": [
    {
      "name": "openssl",
      "current_version": "1.1.1f-1",
      "new_version": "1.1.1f-2",
      "is_security": true
    }
  ]
}
```

### install-updates (Linux) / Install-Updates.ps1 (Windows)

Install updates.

```bash
# Linux
./install-updates.sh [--all|--security|--packages PKG1,PKG2] [--skip-hooks] [--reboot]

# Windows PowerShell
.\Install-Updates.ps1 [-SecurityOnly] [-KBArticles @("KB123")] [-Reboot] [-Quiet]
```

**Output:**
```json
{
  "hostname": "server01",
  "timestamp": "2024-01-15T10:35:00Z",
  "success": true,
  "installed_count": 5,
  "failed_count": 0,
  "reboot_required": true,
  "installed": ["openssl", "curl", "wget"],
  "failed": []
}
```

### check-reboot (Linux) / Check-Reboot.ps1 (Windows)

Check if system requires reboot.

```bash
# Linux
./check-reboot.sh [--services]

# Windows PowerShell
.\Check-Reboot.ps1 [-Quiet]
```

**Output:**
```json
{
  "hostname": "server01",
  "timestamp": "2024-01-15T10:40:00Z",
  "reboot_required": true,
  "reasons": ["kernel update pending"]
}
```

### list-installed (Linux) / Get-InstalledKB.ps1 (Windows)

List installed packages/hotfixes.

```bash
# Linux
./list-installed.sh [--filter PATTERN] [--limit N]

# Windows PowerShell
.\Get-InstalledKB.ps1 [-Limit 100] [-Filter "KB5001"]
```

### rollback (Linux only)

Rollback package updates.

```bash
./rollback.sh --list                    # List rollback options
./rollback.sh --transaction ID          # DNF transaction rollback
./rollback.sh --snapshot ID             # Snapper snapshot restore
./rollback.sh --package PKG --version V # Downgrade specific package
```

### firewall-rules (Linux) / Firewall-Rules.ps1 (Windows)

Intall firewall rules from blacklist IP Address. File [Filename] stores black list.

```bash
# Linux
./firewall-rules.sh [Filename]

# Windows PowerShell
./Firewall-Rules.ps1 [Filename]
```

### setup-proxy (Linux) / Setup-Proxy.ps1 (Windows)

Intall proxy. No Proxy: pattern of hostname, IP Address that traffic doesn't go through a proxy, example: localhost,127.0.0.1,.svc,.cluster.local.

```bash
# Linux
./setup-proxy.sh [IP Address] [Port] [No Proxy]

# Windows PowerShell
./Setup-Proxy.ps1 [IP Address] [Port] [No Proxy]
```

### sync-hosts (Linux)

Synchronize hosts file. File [Filename] stores list host.

```bash
# Linux
./sync-host.sh [Filename]

```

### update-certs (Linux) / Update-Certs.ps1 (Windows)

Update certs list. File [Filename] stores certs filename.

```bash
# Linux
./update-certs.sh [Filename] [import|reset]

# Windows PowerShell
./Update-Certs.ps1 [Filename] [import|reset]
```

### Setup-DNS.ps1 (Windows)

Setup DNS server. DNS Server, example: 8.8.8.8,8.8.4.4 .

```bash
# Windows PowerShell
./Setup-DNS.ps1 [set|reset] [DNS Server]
```

## Hook System

Hooks allow custom actions at specific points in the update process.

### Hook Types

| Type | When | Failure Behavior |
|------|------|------------------|
| `pre-upgrade` | Before installing updates | Aborts update |
| `pre-reboot` | Before reboot (if requested) | Aborts reboot |
| `post-upgrade` | After updates complete | Logs warning, continues |

### Hook Requirements

- Must be executable (`chmod +x`)
- Must exit with code 0 for success
- Should be owned by root
- Should not be world-writable

### Hook Examples

```bash
# Enable a disabled hook
mv hooks.d/pre-upgrade/10-backup-check.sh.disabled \
   hooks.d/pre-upgrade/10-backup-check.sh

# Create custom hook
cat > hooks.d/pre-upgrade/15-custom.sh << 'EOF'
#!/bin/bash
echo "Running custom pre-upgrade check"
# Your logic here
exit 0
EOF
chmod +x hooks.d/pre-upgrade/15-custom.sh
```

### Included Hooks

**Linux:**
- `00-check-disk-space.sh` - Verify >= 1GB free space
- `10-backup-check.sh.disabled` - Verify backup exists
- `20-stop-services.sh.disabled` - Stop services before update
- `00-drain-connections.sh.disabled` - Drain load balancer before reboot
- `00-verify-services.sh` - Verify services running after update
- `10-send-report.sh.disabled` - Send update report

**Windows:**
- `00-Check-DiskSpace.ps1` - Verify >= 5GB free space
- `10-Stop-Services.ps1.disabled` - Stop services before update
- `00-Drain-Connections.ps1.disabled` - Drain connections before reboot
- `00-Verify-Services.ps1` - Verify critical services
- `10-Send-Report.ps1.disabled` - Send update report

## Integration

### NetXMS Agent

Add to `nxagentd.conf`:

```
ExternalParameter = LinuxUpdates:check-updates.sh
ExternalParameter = LinuxReboot:check-reboot.sh
```

### Wazuh

Configure as active response or wodle command.

### Cron/Scheduled Task

```bash
# Linux: /etc/cron.d/linksafe-patch
0 2 * * 0 root /opt/linksafe-patch/actions/check-updates.sh --save >> /var/log/linksafe-patch.log 2>&1
```

```powershell
# Windows: Create scheduled task
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\linksafe-patch\actions\Check-Updates.ps1"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
Register-ScheduledTask -TaskName "LINKSAFE-CheckUpdates" -Action $Action -Trigger $Trigger
```

## State Management

State files are stored in `state/` directory:

- `last-check.json` - Last update check results
- `last-install.json` - Last installation results
- `history/` - Historical records

## Testing

```bash
# Linux
./tests/test-linux.sh

# Windows PowerShell
.\tests\Test-Windows.ps1
```

## Requirements

### Linux
- Bash 4.0+
- Python 3 (for JSON validation in tests)
- Root access for update operations

### Windows
- PowerShell 5.1+
- Administrator access for update operations

## License

Part of LINKSAFE Security Platform.
