# =============================================================================
# Module 01 - Lab Setup (Admin)
# OpenRaptor Cyber Range - OD@CIRT.APAC
#
# Run on SP01 as Farm Admin (or on DC01 with remote SP management).
# Sets up all scenario prerequisites for Module 01 (SharePoint Webshell).
#
# What this script does:
#   1. Creates cirtstudent AD account (student login)
#   2. Creates j.chen AD account (compromised Finance analyst - scenario only)
#   3. Grants j.chen Contribute access to SharePoint Shared Documents library
#      (required for WebDAV upload of webshell — this is the attack vector)
#   4. Verifies SP01 is in clean state (no webshell present)
#   5. Runs lab_01_check.ps1 to verify everything is ready
#
# NOTE: Steps 1-2 run on DC01 (AD). Step 3 MUST run on SP01 as Farm Admin.
#       Run this entire script on SP01 via Bastion RDP, or run steps 1-2 on
#       DC01 and step 3 separately on SP01.
# =============================================================================

param(
    [string]$SPUrl      = "http://sharepoint.norca.click",
    [string]$SiteUrl    = "http://sharepoint.norca.click",
    [string]$ListName   = "Shared Documents",
    [switch]$SkipAD     = $false,
    [switch]$SkipSP     = $false
)

$ErrorActionPreference = "Continue"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Module 01 — Lab Setup                        ║" -ForegroundColor Yellow
Write-Host "║  Run as: Farm Admin on SP01 (or DC01 for AD) ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

$studentPassPlain = $env:CIRT_STUDENT_PASSWORD
# CIRT_STUDENT_PASSWORD env var must be set before running this script (see team/DECISIONS.md for value)
if (-not $studentPassPlain) { throw "CIRT_STUDENT_PASSWORD env var not set. Aborting." }
$password = ConvertTo-SecureString $studentPassPlain -AsPlainText -Force

# =============================================================================
# STEP 1 + 2: AD Account Setup (requires AD module — run on DC01 or SP01)
# =============================================================================
if (-not $SkipAD) {
    Write-Host "[1/4] Setting up AD accounts..." -ForegroundColor Yellow

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        # cirtstudent — student login account
        if (-not (Get-ADUser -Filter {SamAccountName -eq "cirtstudent"} -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "CIRT Student" `
                -SamAccountName "cirtstudent" `
                -UserPrincipalName "cirtstudent@norca.click" `
                -AccountPassword $password `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -Path "CN=Users,DC=norca,DC=click" `
                -Description "Student login account - lab exercises"
            Write-Host "  [OK] Created cirtstudent" -ForegroundColor Green
        } else {
            Set-ADAccountPassword -Identity "cirtstudent" -Reset -NewPassword $password
            Enable-ADAccount -Identity "cirtstudent"
            Write-Host "  [SKIP] cirtstudent already exists — password reset" -ForegroundColor Yellow
        }

        # j.chen — compromised Finance analyst account (scenario attack vector)
        if (-not (Get-ADUser -Filter {SamAccountName -eq "j.chen"} -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "Jenny Chen" `
                -GivenName "Jenny" `
                -Surname "Chen" `
                -SamAccountName "j.chen" `
                -UserPrincipalName "j.chen@norca.click" `
                -AccountPassword $password `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -Path "CN=Users,DC=norca,DC=click" `
                -Description "Finance Analyst - Module 01 scenario account"
            Write-Host "  [OK] Created j.chen (Jenny Chen)" -ForegroundColor Green
        } else {
            Set-ADAccountPassword -Identity "j.chen" -Reset -NewPassword $password
            Enable-ADAccount -Identity "j.chen"
            Write-Host "  [SKIP] j.chen already exists — password reset" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] AD module not available: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Run this script on DC01 or a domain-joined server with RSAT" -ForegroundColor Yellow
    }
} else {
    Write-Host "[1/4] Skipping AD account setup (–SkipAD)" -ForegroundColor Yellow
}

# =============================================================================
# STEP 3: Grant j.chen Contribute on Shared Documents (MUST run on SP01)
#
# WHY: This is the attack vector. j.chen needs Contribute so the attacker
#      can upload help.aspx via WebDAV. Without this, upload returns 403.
#      Contribute on the document library is a realistic permission level for
#      a Finance analyst who uploads reports to SharePoint.
# =============================================================================
if (-not $SkipSP) {
    Write-Host "[2/4] Granting j.chen Contribute on SharePoint Shared Documents..." -ForegroundColor Yellow

    try {
        # Load SharePoint snap-in (available on SP01 only)
        if (-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
            Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
        }

        $web  = Get-SPWeb $SiteUrl -ErrorAction Stop
        $list = $web.Lists[$ListName]

        if ($null -eq $list) {
            Write-Host "  [FAIL] List '$ListName' not found at $SiteUrl" -ForegroundColor Red
            Write-Host "         Check SharePoint is fully started (post-deploy log: C:\Windows\Temp\post-deploy.log)" -ForegroundColor Red
        } else {
            # Break list-level permission inheritance if not already broken
            if (-not $list.HasUniqueRoleAssignments) {
                $list.BreakRoleInheritance($true)  # $true = copy existing perms
                Write-Host "  [OK] Broke permission inheritance on '$ListName'" -ForegroundColor Green
            }

            # Resolve j.chen as SP user (creates the SPUser entry if first login)
            $user = $web.EnsureUser("NORCA\j.chen")
            $roleAssignment = New-Object Microsoft.SharePoint.SPRoleAssignment($user)

            # Contribute = can add/edit/delete items (needed for WebDAV PUT of .aspx)
            $role = $web.RoleDefinitions["Contribute"]
            if ($null -eq $role) {
                # Fallback: some SP installations use localized names
                $role = $web.RoleDefinitions | Where-Object { $_.BasePermissions -band [Microsoft.SharePoint.SPBasePermissions]::AddListItems } | Select-Object -First 1
            }
            $roleAssignment.RoleDefinitionBindings.Add($role)
            $list.RoleAssignments.Add($roleAssignment)
            $list.Update()

            Write-Host "  [OK] j.chen granted '$($role.Name)' on '$ListName'" -ForegroundColor Green
            Write-Host "       (This enables WebDAV PUT of help.aspx — the attack vector)" -ForegroundColor Cyan
        }

        $web.Dispose()

    } catch {
        Write-Host "  [FAIL] SharePoint permission grant failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "         Ensure this script is running on SP01 with Farm Admin privileges" -ForegroundColor Red
        Write-Host "         Alternatively, grant manually: SharePoint → Site Settings → Site permissions → '$ListName'" -ForegroundColor Yellow
    }
} else {
    Write-Host "[2/4] Skipping SP permission setup (–SkipSP)" -ForegroundColor Yellow
}

# =============================================================================
# STEP 4: Verify SP01 clean state
# =============================================================================
Write-Host "[3/4] Verifying SP01 clean state..." -ForegroundColor Yellow

try {
    $cred = New-Object PSCredential("NORCA\j.chen", $password)
    $response = Invoke-WebRequest -Uri "$SPUrl/Shared%20Documents/help.aspx" `
        -Credential $cred -UseBasicParsing -ErrorAction Stop
    Write-Host "  [WARN] help.aspx already exists on SP01 — lab needs reset" -ForegroundColor Red
} catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
        Write-Host "  [OK] SP01 is clean (help.aspx not present)" -ForegroundColor Green
    } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "  [OK] SP01 is clean (auth required, no webshell)" -ForegroundColor Green
    } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 403) {
        Write-Host "  [WARN] j.chen got 403 on Shared Documents — SP permission step may have failed" -ForegroundColor Yellow
        Write-Host "         Re-run without –SkipSP on SP01 to grant Contribute access" -ForegroundColor Yellow
    } else {
        Write-Host "  [WARN] Could not verify SP01 state: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# =============================================================================
# STEP 5: Run check script
# =============================================================================
Write-Host "[4/4] Running lab check..." -ForegroundColor Yellow
$checkScript = Join-Path $PSScriptRoot "lab_01_check.ps1"
if (Test-Path $checkScript) {
    & $checkScript
} else {
    Write-Host "  [SKIP] lab_01_check.ps1 not found — run manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Cyan
Write-Host "If all checks pass, hand off to student." -ForegroundColor Cyan
