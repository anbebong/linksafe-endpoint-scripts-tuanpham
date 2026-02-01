# LINKSAFE Patch Management Architecture

## Data Flow Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              DATA SOURCES                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────────┐ │
│  │ WAZUH AGENT  │     │ NETXMS AGENT │     │     LINKSAFE PATCH SCRIPTS       │ │
│  │              │     │              │     │                                  │ │
│  │ syscollector │     │ Object Tools │────▶│ check-updates.sh / .ps1          │ │
│  │ (packages)   │     │ (execute)    │     │ install-updates.sh / .ps1        │ │
│  │              │     │              │     │                                  │ │
│  │ vulnerability│     │              │     │ Output: LOG: and DATA: prefix    │ │
│  │ (CVE scan)   │     │              │     │                                  │ │
│  └──────┬───────┘     └──────┬───────┘     └──────────────────────────────────┘ │
│         │                    │                                                   │
└─────────┼────────────────────┼───────────────────────────────────────────────────┘
          │                    │
          ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         INTEGRATION LAYER                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐          ┌────────────────────────────────────────────────┐   │
│  │ WAZUH PLUGIN │          │              NETXMS PLUGIN                     │   │
│  │              │          │                                                │   │
│  │ get_packages │          │ execute_object_tool      → Start async exec    │   │
│  │ get_vulns    │          │ get_object_tool_output   → Poll for output     │   │
│  │              │          │ execute_object_tool_sync → Combined (polling)  │   │
│  │              │          │                                                │   │
│  │              │          │ parseScriptOutput()      → Parse LOG:/DATA:    │   │
│  └──────┬───────┘          └─────────────────┬──────────────────────────────┘   │
│         │                                    │                                   │
└─────────┼────────────────────────────────────┼───────────────────────────────────┘
          │                                    │
          ▼                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DEVICE SERVICE                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    CapabilityExecutor                                    │    │
│  │                                                                          │    │
│  │  sync_packages      → Wazuh syscollector → device_packages table         │    │
│  │  sync_vulnerabilities → Wazuh vuln detector → device_vulnerabilities     │    │
│  │  check_updates      → NetXMS Object Tool → device_available_updates      │    │
│  │  install_updates    → NetXMS Object Tool → patch_executions              │    │
│  │                                                                          │    │
│  │  Data Merge:                                                             │    │
│  │  - Correlate packages with CVEs                                          │    │
│  │  - Map available updates with installed packages                         │    │
│  │  - Calculate patch priority based on CVE severity                        │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         DATABASE                                         │    │
│  │                                                                          │    │
│  │  device_packages           → Installed software inventory                │    │
│  │  device_vulnerabilities    → CVE findings per device                     │    │
│  │  device_available_updates  → Pending updates per device                  │    │
│  │  patch_executions          → Execution history & audit trail             │    │
│  │                                                                          │    │
│  │  v_package_patch_status    → Combined view for dashboard                 │    │
│  │                                                                          │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## API Flow Examples

### 1. Check Updates (Async with Polling)

```
Frontend                Device Service              NetXMS Plugin             NetXMS Agent
   │                         │                           │                         │
   │  POST /check-updates    │                           │                         │
   │────────────────────────▶│                           │                         │
   │                         │                           │                         │
   │                         │  execute_object_tool_sync │                         │
   │                         │──────────────────────────▶│                         │
   │                         │                           │                         │
   │                         │                           │  POST /object-tools     │
   │                         │                           │────────────────────────▶│
   │                         │                           │                         │
   │                         │                           │  { "UUID": "xxx" }      │
   │                         │                           │◀────────────────────────│
   │                         │                           │                         │
   │                         │                           │  GET /output/{uuid}     │
   │                         │                           │────────────────────────▶│
   │                         │                           │  (polling loop)         │
   │                         │                           │◀────────────────────────│
   │                         │                           │                         │
   │                         │  parsed result            │                         │
   │                         │◀──────────────────────────│                         │
   │                         │                           │                         │
   │                         │  Save to device_available_updates                   │
   │                         │  Correlate with CVEs                                │
   │                         │                           │                         │
   │  { updates, cves }      │                           │                         │
   │◀────────────────────────│                           │                         │
```

### 2. Install Updates (Async with Status Tracking)

```
Frontend                Device Service              NetXMS Plugin             NetXMS Agent
   │                         │                           │                         │
   │  POST /install-updates  │                           │                         │
   │  { packages: [...] }    │                           │                         │
   │────────────────────────▶│                           │                         │
   │                         │                           │                         │
   │                         │  Create patch_execution   │                         │
   │                         │  record (status=pending)  │                         │
   │                         │                           │                         │
   │  { execution_id: xxx }  │                           │                         │
   │◀────────────────────────│                           │                         │
   │                         │                           │                         │
   │                         │  execute_object_tool      │                         │
   │                         │  (async)                  │                         │
   │                         │──────────────────────────▶│                         │
   │                         │                           │────────────────────────▶│
   │                         │                           │  { "UUID": "yyy" }      │
   │                         │                           │◀────────────────────────│
   │                         │                           │                         │
   │                         │  Update execution         │                         │
   │                         │  (status=running)         │                         │
   │                         │                           │                         │
   │  GET /execution/{id}    │                           │                         │
   │────────────────────────▶│                           │                         │
   │  { status: running }    │                           │                         │
   │◀────────────────────────│                           │                         │
   │                         │                           │                         │
   │        ... (polling) ...                            │                         │
   │                         │                           │                         │
   │                         │  get_object_tool_output   │                         │
   │                         │──────────────────────────▶│                         │
   │                         │                           │────────────────────────▶│
   │                         │  completed result         │                         │
   │                         │◀──────────────────────────│                         │
   │                         │                           │                         │
   │                         │  Update execution         │                         │
   │                         │  (status=success)         │                         │
   │                         │  Update available_updates │                         │
   │                         │  (status=installed)       │                         │
   │                         │                           │                         │
   │  GET /execution/{id}    │                           │                         │
   │────────────────────────▶│                           │                         │
   │  { status: success,     │                           │                         │
   │    packages_updated }   │                           │                         │
   │◀────────────────────────│                           │                         │
```

## Database Tables Relationship

```
                    ┌─────────────────────┐
                    │      devices        │
                    │                     │
                    │  id                 │
                    │  tenant_id          │
                    │  hostname           │
                    │  os_type            │
                    └─────────┬───────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ device_packages │  │ device_vulns    │  │ device_updates  │
│                 │  │                 │  │                 │
│ id              │  │ id              │  │ id              │
│ device_id (FK)  │  │ device_id (FK)  │  │ device_id (FK)  │
│ name            │◀─│ package_id (FK) │  │ package_id (FK) │─▶│
│ version         │  │ cve_id          │  │ package_name    │
│ architecture    │  │ severity        │  │ available_ver   │
│ source: wazuh   │  │ fixed_version   │  │ is_security     │
│                 │  │ status          │  │ status          │
│                 │  │ source: wazuh   │  │ source: script  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
                              │
                              │ JOIN on package_name
                              ▼
                    ┌─────────────────────┐
                    │ v_package_patch_    │
                    │ status (VIEW)       │
                    │                     │
                    │ package_name        │
                    │ installed_version   │
                    │ available_version   │
                    │ cve_count           │
                    │ max_severity        │
                    │ cve_ids[]           │
                    └─────────────────────┘
```

## NetXMS Object Tool Setup

### Required Object Tools in NetXMS

```
Tool ID: 10017 (example)
Name: LINKSAFE Check Updates
Type: Agent Command
Command: /opt/linksafe-patch/actions/check-updates.sh

Tool ID: 10018 (example)
Name: LINKSAFE Install Updates
Type: Agent Command
Command: /opt/linksafe-patch/actions/install-updates.sh
Requires confirmation: Yes

Tool ID: 10019 (example)
Name: LINKSAFE Check Updates (Windows)
Type: Agent Command
Command: powershell.exe -ExecutionPolicy Bypass -File C:\linksafe-patch\actions\Check-Updates.ps1 -IncludeWinget
```

## Script Output Format

All scripts output in prefix format for easy parsing:

```
LOG:2024-01-15T10:30:00Z:INFO:Starting update check...
LOG:2024-01-15T10:30:05Z:INFO:Found 47 updates (12 security)
DATA:{"hostname":"server1","updates":{"total":47,"security":12,"packages":[...]}}
```

Plugin parses this into structured format:
```json
{
  "execution_uuid": "xxx-xxx-xxx",
  "status": "completed",
  "parsed": {
    "logs": [
      {"timestamp": "2024-01-15T10:30:00Z", "level": "INFO", "message": "Starting update check..."},
      {"timestamp": "2024-01-15T10:30:05Z", "level": "INFO", "message": "Found 47 updates (12 security)"}
    ],
    "data": {
      "hostname": "server1",
      "updates": {"total": 47, "security": 12, "packages": [...]}
    }
  }
}
```

## Priority Calculation

Device Service calculates patch priority based on:

1. **CVE Severity** (highest weight)
   - Critical: 100 points
   - High: 75 points
   - Medium: 50 points
   - Low: 25 points

2. **Security Update Flag** (+30 points)

3. **Age of Update** (days since detected)
   - > 30 days: +20 points
   - > 7 days: +10 points

4. **System Type**
   - Production: x1.5 multiplier
   - Development: x1.0 multiplier

```sql
-- Example priority query
SELECT
    u.package_name,
    u.available_version,
    COALESCE(MAX(CASE v.severity
        WHEN 'Critical' THEN 100
        WHEN 'High' THEN 75
        WHEN 'Medium' THEN 50
        ELSE 25
    END), 0) +
    CASE WHEN u.is_security THEN 30 ELSE 0 END +
    CASE
        WHEN u.detected_at < NOW() - INTERVAL '30 days' THEN 20
        WHEN u.detected_at < NOW() - INTERVAL '7 days' THEN 10
        ELSE 0
    END AS priority_score
FROM device_available_updates u
LEFT JOIN device_vulnerabilities v ON u.device_id = v.device_id AND u.package_name = v.package_name
WHERE u.device_id = $1 AND u.status = 'pending'
GROUP BY u.id
ORDER BY priority_score DESC;
```
