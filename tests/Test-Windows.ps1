#Requires -Version 5.1
<#
.SYNOPSIS
    LINKSAFE Patch Management - Windows Test Suite

.DESCRIPTION
    Runs tests for Windows patch management scripts

.PARAMETER Test
    Specific test to run (Module, CheckUpdates, CheckReboot, Hooks, All)

.EXAMPLE
    .\Test-Windows.ps1
    .\Test-Windows.ps1 -Test Module
#>

[CmdletBinding()]
param(
    [ValidateSet("Module", "CheckUpdates", "CheckReboot", "Hooks", "All")]
    [string]$Test = "All"
)

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$WindowsDir = Join-Path $ScriptRoot "windows"

$TestsPassed = 0
$TestsFailed = 0
$TestsSkipped = 0

function Write-Pass {
    param([string]$Message)
    Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    $script:TestsPassed++
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    $script:TestsFailed++
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  [SKIP] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    $script:TestsSkipped++
}

function Test-ValidJson {
    param([string]$JsonString, [string]$TestName)

    try {
        $null = $JsonString | ConvertFrom-Json
        Write-Pass "$TestName produces valid JSON"
        return $true
    } catch {
        Write-Fail "$TestName produces invalid JSON: $_"
        return $false
    }
}

function Test-JsonHasField {
    param([string]$JsonString, [string]$FieldName, [string]$TestName)

    try {
        $obj = $JsonString | ConvertFrom-Json
        if ($obj.PSObject.Properties.Name -contains $FieldName) {
            Write-Pass "$TestName has field '$FieldName'"
            return $true
        } else {
            Write-Fail "$TestName missing field '$FieldName'"
            return $false
        }
    } catch {
        Write-Fail "$TestName JSON parse error: $_"
        return $false
    }
}

# ============================================================================
# Test: Module Loading
# ============================================================================
function Test-ModuleLoading {
    Write-Host ""
    Write-Host "=== Testing Module Loading ===" -ForegroundColor Cyan

    $modulePath = Join-Path $WindowsDir "lib\WindowsUpdate.psm1"

    if (Test-Path $modulePath) {
        Write-Pass "WindowsUpdate.psm1 exists"
    } else {
        Write-Fail "WindowsUpdate.psm1 not found at $modulePath"
        return
    }

    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Pass "WindowsUpdate.psm1 loads successfully"
    } catch {
        Write-Fail "WindowsUpdate.psm1 failed to load: $_"
        return
    }

    # Check exported functions
    $expectedFunctions = @(
        "Get-AvailableUpdates",
        "Install-WindowsUpdates",
        "Get-PendingReboot",
        "Get-InstalledKBs",
        "Write-PatchLog"
    )

    foreach ($func in $expectedFunctions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            Write-Pass "Function exported: $func"
        } else {
            Write-Fail "Function not exported: $func"
        }
    }
}

# ============================================================================
# Test: Check Updates Script
# ============================================================================
function Test-CheckUpdates {
    Write-Host ""
    Write-Host "=== Testing Check-Updates.ps1 ===" -ForegroundColor Cyan

    $script = Join-Path $WindowsDir "actions\Check-Updates.ps1"

    if (-not (Test-Path $script)) {
        Write-Fail "Check-Updates.ps1 not found"
        return
    }

    Write-Pass "Check-Updates.ps1 exists"

    # Test syntax
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
        Write-Pass "Check-Updates.ps1 has valid syntax"
    } catch {
        Write-Fail "Check-Updates.ps1 syntax error: $_"
        return
    }

    # Test execution (may need admin)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        try {
            $output = & $script -Quiet 2>&1
            if ($output) {
                Test-ValidJson $output "Check-Updates.ps1"
                Test-JsonHasField $output "hostname" "Check-Updates.ps1"
                Test-JsonHasField $output "updates" "Check-Updates.ps1"
            }
        } catch {
            Write-Fail "Check-Updates.ps1 execution error: $_"
        }
    } else {
        Write-Skip "Check-Updates.ps1 execution requires Administrator"
    }
}

# ============================================================================
# Test: Check Reboot Script
# ============================================================================
function Test-CheckReboot {
    Write-Host ""
    Write-Host "=== Testing Check-Reboot.ps1 ===" -ForegroundColor Cyan

    $script = Join-Path $WindowsDir "actions\Check-Reboot.ps1"

    if (-not (Test-Path $script)) {
        Write-Fail "Check-Reboot.ps1 not found"
        return
    }

    Write-Pass "Check-Reboot.ps1 exists"

    # Test syntax
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
        Write-Pass "Check-Reboot.ps1 has valid syntax"
    } catch {
        Write-Fail "Check-Reboot.ps1 syntax error: $_"
        return
    }

    # Test execution
    try {
        $output = & $script 2>&1
        if ($output) {
            Test-ValidJson $output "Check-Reboot.ps1"
            Test-JsonHasField $output "reboot_required" "Check-Reboot.ps1"
        }
    } catch {
        Write-Fail "Check-Reboot.ps1 execution error: $_"
    }
}

# ============================================================================
# Test: Hooks
# ============================================================================
function Test-Hooks {
    Write-Host ""
    Write-Host "=== Testing Hooks System ===" -ForegroundColor Cyan

    $hookDirs = @(
        "pre-upgrade",
        "pre-reboot",
        "post-upgrade"
    )

    foreach ($dir in $hookDirs) {
        $hookPath = Join-Path $WindowsDir "hooks.d\$dir"
        if (Test-Path $hookPath) {
            Write-Pass "Hook directory exists: $dir"

            $scripts = Get-ChildItem $hookPath -Filter "*.ps1" -ErrorAction SilentlyContinue
            Write-Host "    Found $($scripts.Count) active hook(s)" -ForegroundColor Gray
        } else {
            Write-Fail "Hook directory missing: $dir"
        }
    }

    # Test hook script syntax
    $allHooks = Get-ChildItem (Join-Path $WindowsDir "hooks.d") -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue

    foreach ($hook in $allHooks) {
        try {
            $null = [System.Management.Automation.Language.Parser]::ParseFile($hook.FullName, [ref]$null, [ref]$null)
            Write-Pass "Hook syntax valid: $($hook.Name)"
        } catch {
            Write-Fail "Hook syntax error: $($hook.Name) - $_"
        }
    }
}

# ============================================================================
# Main
# ============================================================================
Write-Host "========================================"
Write-Host "LINKSAFE Patch Management - Windows Tests"
Write-Host "========================================"
Write-Host "Project Root: $ScriptRoot"
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

switch ($Test) {
    "Module" { Test-ModuleLoading }
    "CheckUpdates" { Test-CheckUpdates }
    "CheckReboot" { Test-CheckReboot }
    "Hooks" { Test-Hooks }
    "All" {
        Test-ModuleLoading
        Test-CheckUpdates
        Test-CheckReboot
        Test-Hooks
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "Test Summary"
Write-Host "========================================"
Write-Host "  Passed:  $TestsPassed" -ForegroundColor Green
Write-Host "  Failed:  $TestsFailed" -ForegroundColor Red
Write-Host "  Skipped: $TestsSkipped" -ForegroundColor Yellow

if ($TestsFailed -gt 0) {
    exit 1
}
