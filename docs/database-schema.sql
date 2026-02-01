-- =============================================================================
-- LINKSAFE Patch Management - Database Schema
-- =============================================================================
-- Lưu trữ dữ liệu từ Wazuh + Patch Scripts để enable:
-- - Filter packages by CVE
-- - Map available updates với installed packages
-- - Dashboard metrics & reporting
-- =============================================================================

-- Package Inventory (từ Wazuh syscollector)
CREATE TABLE device_packages (
    id BIGSERIAL PRIMARY KEY,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    tenant_id VARCHAR(50) NOT NULL,

    -- Package info
    name VARCHAR(255) NOT NULL,
    version VARCHAR(100),
    architecture VARCHAR(50),
    vendor VARCHAR(255),
    description TEXT,
    install_time TIMESTAMP,

    -- Source tracking
    source VARCHAR(50) DEFAULT 'wazuh',  -- wazuh, netxms, manual

    -- Timestamps
    first_seen_at TIMESTAMP DEFAULT NOW(),
    last_seen_at TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique
    UNIQUE(device_id, name, architecture)
);

CREATE INDEX idx_device_packages_device ON device_packages(device_id);
CREATE INDEX idx_device_packages_name ON device_packages(name);
CREATE INDEX idx_device_packages_tenant ON device_packages(tenant_id);

-- CVE Vulnerabilities (từ Wazuh vulnerability detector)
CREATE TABLE device_vulnerabilities (
    id BIGSERIAL PRIMARY KEY,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    tenant_id VARCHAR(50) NOT NULL,
    package_id BIGINT REFERENCES device_packages(id) ON DELETE SET NULL,

    -- CVE info
    cve_id VARCHAR(50) NOT NULL,  -- CVE-2024-1234
    severity VARCHAR(20),          -- Critical, High, Medium, Low
    cvss_score DECIMAL(3,1),

    -- Affected package
    package_name VARCHAR(255) NOT NULL,
    package_version VARCHAR(100),
    fixed_version VARCHAR(100),    -- Version that fixes this CVE

    -- Status
    status VARCHAR(20) DEFAULT 'open',  -- open, patched, ignored, false_positive

    -- Reference
    reference_url TEXT,
    description TEXT,

    -- Source
    source VARCHAR(50) DEFAULT 'wazuh',

    -- Timestamps
    detected_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(device_id, cve_id, package_name)
);

CREATE INDEX idx_device_vulns_device ON device_vulnerabilities(device_id);
CREATE INDEX idx_device_vulns_cve ON device_vulnerabilities(cve_id);
CREATE INDEX idx_device_vulns_severity ON device_vulnerabilities(severity);
CREATE INDEX idx_device_vulns_status ON device_vulnerabilities(status);
CREATE INDEX idx_device_vulns_tenant ON device_vulnerabilities(tenant_id);

-- Available Updates (từ Patch Scripts)
CREATE TABLE device_available_updates (
    id BIGSERIAL PRIMARY KEY,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    tenant_id VARCHAR(50) NOT NULL,
    package_id BIGINT REFERENCES device_packages(id) ON DELETE SET NULL,

    -- Update info
    package_name VARCHAR(255) NOT NULL,
    current_version VARCHAR(100),
    available_version VARCHAR(100) NOT NULL,
    architecture VARCHAR(50),
    repository VARCHAR(255),

    -- Classification
    is_security BOOLEAN DEFAULT FALSE,
    severity VARCHAR(20),           -- Critical, Important, Moderate, Low

    -- Size
    size_bytes BIGINT,

    -- For Windows
    kb_articles JSONB,              -- ["KB5001234", "KB5005678"]

    -- Status
    status VARCHAR(20) DEFAULT 'pending',  -- pending, approved, installed, failed, ignored

    -- Source
    source VARCHAR(50),             -- apt, dnf, zypper, WindowsUpdate, Winget

    -- Timestamps
    detected_at TIMESTAMP DEFAULT NOW(),
    approved_at TIMESTAMP,
    installed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(device_id, package_name, available_version)
);

CREATE INDEX idx_device_updates_device ON device_available_updates(device_id);
CREATE INDEX idx_device_updates_security ON device_available_updates(is_security);
CREATE INDEX idx_device_updates_status ON device_available_updates(status);
CREATE INDEX idx_device_updates_tenant ON device_available_updates(tenant_id);

-- Patch Execution History
CREATE TABLE patch_executions (
    id BIGSERIAL PRIMARY KEY,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    tenant_id VARCHAR(50) NOT NULL,

    -- Execution info
    execution_id VARCHAR(100) UNIQUE,  -- UUID from NetXMS or internal
    action VARCHAR(50) NOT NULL,       -- check, install, install_security

    -- Status
    status VARCHAR(20) DEFAULT 'pending',  -- pending, running, success, partial, failed

    -- Request
    requested_packages JSONB,          -- Specific packages or null for all
    parameters JSONB,

    -- Result
    result JSONB,                      -- Full JSON result from script
    packages_updated JSONB,
    error_message TEXT,

    -- Timing
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    duration_seconds INT,

    -- Reboot
    reboot_required BOOLEAN DEFAULT FALSE,
    rebooted_at TIMESTAMP,

    -- Audit
    initiated_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_patch_exec_device ON patch_executions(device_id);
CREATE INDEX idx_patch_exec_status ON patch_executions(status);
CREATE INDEX idx_patch_exec_tenant ON patch_executions(tenant_id);

-- View: Packages with CVEs and Updates
CREATE OR REPLACE VIEW v_package_patch_status AS
SELECT
    p.device_id,
    p.tenant_id,
    p.name AS package_name,
    p.version AS installed_version,
    p.architecture,
    u.available_version,
    u.is_security AS has_security_update,
    u.status AS update_status,
    COUNT(DISTINCT v.cve_id) AS cve_count,
    MAX(v.severity) AS max_severity,
    ARRAY_AGG(DISTINCT v.cve_id) FILTER (WHERE v.cve_id IS NOT NULL) AS cve_ids
FROM device_packages p
LEFT JOIN device_available_updates u
    ON p.device_id = u.device_id AND p.name = u.package_name
LEFT JOIN device_vulnerabilities v
    ON p.device_id = v.device_id AND p.name = v.package_name AND v.status = 'open'
GROUP BY p.device_id, p.tenant_id, p.name, p.version, p.architecture,
         u.available_version, u.is_security, u.status;
