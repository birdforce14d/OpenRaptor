# SP01 Post-Deploy Bootstrap
# Runs automatically after deployment from golden image via Azure Custom Script Extension
# Stage 1: Wait for DC01 reachability, domain rejoin (with retry), schedule Stage 2
# Stage 2: Grant logon rights, reset app pool identity, start SP services

$LogFile    = "C:\Windows\Temp\post-deploy.log"
$Stage2Flag = "C:\Windows\Temp\post-deploy-stage2.flag"
$ScriptPath = "C:\Windows\Temp\post-deploy.ps1"

function Write-Log {
    param($msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append
}

$AdminUser     = "NORCA\cirtadmin"
$AdminPassword = "Norca@2024!"
$Domain        = "norca.click"
$DcIP          = "10.10.1.10"
$AppPoolName   = "SharePoint - 80"
$SecurePass    = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Cred          = New-Object System.Management.Automation.PSCredential($AdminUser, $SecurePass)

# Helper: grant a logon right via LSA API (survives GP refresh, no secedit needed)
function Grant-LogonRight {
    param([string]$Account, [string]$Right)
    $code = @'
using System;
using System.Runtime.InteropServices;
public class LsaApi {
    [DllImport("advapi32",CharSet=CharSet.Unicode)]
    static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING sys, ref LSA_OBJECT_ATTRIBUTES attr, int access, out IntPtr handle);
    [DllImport("advapi32",CharSet=CharSet.Unicode)]
    static extern uint LsaAddAccountRights(IntPtr handle, IntPtr sid, LSA_UNICODE_STRING[] rights, int count);
    [DllImport("advapi32")] static extern int LsaNtStatusToWinError(uint s);
    [DllImport("advapi32")] static extern uint LsaClose(IntPtr h);
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public int Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; [MarshalAs(UnmanagedType.LPWStr)] public string Buffer; }
    public static void Add(string account, string right) {
        var sid = new System.Security.Principal.NTAccount(account).Translate(typeof(System.Security.Principal.SecurityIdentifier));
        byte[] b = new byte[((System.Security.Principal.SecurityIdentifier)sid).BinaryLength];
        ((System.Security.Principal.SecurityIdentifier)sid).GetBinaryForm(b,0);
        IntPtr p = Marshal.AllocHGlobal(b.Length); Marshal.Copy(b,0,p,b.Length);
        LSA_OBJECT_ATTRIBUTES a = new LSA_OBJECT_ATTRIBUTES();
        LSA_UNICODE_STRING s = new LSA_UNICODE_STRING(); IntPtr pol;
        LsaOpenPolicy(ref s,ref a,0x00020000|0x00000800,out pol);
        var r = new LSA_UNICODE_STRING[]{new LSA_UNICODE_STRING{Buffer=right,Length=(ushort)(right.Length*2),MaximumLength=(ushort)(right.Length*2+2)}};
        uint res=LsaAddAccountRights(pol,p,r,1); LsaClose(pol); Marshal.FreeHGlobal(p);
        if(res!=0) throw new Exception("LSA error: "+LsaNtStatusToWinError(res));
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'LsaApi').Type) {
        Add-Type -TypeDefinition $code -Language CSharp
    }
    [LsaApi]::Add($Account, $Right)
}

# -- Stage 2: post-reboot service startup -------------------------------------
if (Test-Path $Stage2Flag) {
    Write-Log "=== STAGE 2: Post-reboot service startup ==="

    # Wait for domain membership to settle (up to 5 min)
    Write-Log "Waiting for domain..."
    for ($r = 1; $r -le 30; $r++) {
        try {
            [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain() | Out-Null
            Write-Log "Domain reachable."
            break
        } catch {
            Write-Log "Not ready ($r/30), waiting 10s..."
            Start-Sleep 10
        }
    }


    # Fix SQL logins (SID mismatch after domain rebuild from golden image)
    # The golden image SQL has svc-sp-farm/svc-sp-app logins with the original domain SID.
    # After fresh DC01, those SIDs don't exist -- and cirtadmin has no SQL perms either.
    # Solution: restart SQL in single-user mode (-m), which grants local admin sysadmin,
    # then use that to recreate the SP logins with the current domain SIDs.
    Write-Log "Fixing SQL logins via single-user mode recovery..."
    $sqlInstance = "MSSQL`$SHAREPOINT"
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL13.SHAREPOINT\MSSQLServer\Parameters"
    try {
        # Add -m startup param
        $existing = (Get-ItemProperty $regPath -ErrorAction Stop).PSObject.Properties | Where-Object { $_.Name -like "SQLArg*" }
        $nextIdx = ($existing | ForEach-Object { [int]($_.Name -replace 'SQLArg','') } | Measure-Object -Maximum).Maximum + 1
        New-ItemProperty -Path $regPath -Name "SQLArg$nextIdx" -Value "-m" -PropertyType String -Force | Out-Null
        Write-Log "  Added -m as SQLArg$nextIdx"

        # Restart SQL in single-user mode
        Restart-Service $sqlInstance -Force
        Start-Sleep 10
        Write-Log "  SQL in single-user mode"

        # Grant sysadmin to local cirtadmin
        $grantSql = "C:\Windows\Temp\grant-sysadmin.sql"
        @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'win-norca-sp01\cirtadmin')
    CREATE LOGIN [win-norca-sp01\cirtadmin] FROM WINDOWS;
GO
ALTER SERVER ROLE sysadmin ADD MEMBER [win-norca-sp01\cirtadmin];
GO
PRINT 'sysadmin granted';
GO
"@ | Set-Content $grantSql -Encoding ASCII
        $gOut = sqlcmd -S "localhost\SHAREPOINT" -i $grantSql 2>&1
        Write-Log "  Grant result: $($gOut -join ' | ')"

        # Remove -m and restart normally
        Remove-ItemProperty -Path $regPath -Name "SQLArg$nextIdx" -Force
        Restart-Service $sqlInstance -Force
        Start-Sleep 10
        Write-Log "  SQL back in multi-user mode"

        # Now recreate SP logins with correct current-domain SIDs
        $fixSql = "C:\Windows\Temp\fix-sp-sql.sql"
        @"
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'NORCA\svc-sp-farm') DROP LOGIN [NORCA\svc-sp-farm];
GO
CREATE LOGIN [NORCA\svc-sp-farm] FROM WINDOWS;
GO
ALTER SERVER ROLE sysadmin ADD MEMBER [NORCA\svc-sp-farm];
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'NORCA\svc-sp-app') DROP LOGIN [NORCA\svc-sp-app];
GO
CREATE LOGIN [NORCA\svc-sp-app] FROM WINDOWS;
GO
SELECT name, is_disabled FROM sys.server_principals WHERE name LIKE N'NORCA%' ORDER BY name;
GO
"@ | Set-Content $fixSql -Encoding ASCII
        $fixOut = sqlcmd -S "localhost\SHAREPOINT" -E -i $fixSql 2>&1
        Write-Log "  SP logins fixed: $($fixOut -join ' | ')"
    } catch {
        Write-Log "  WARNING: SQL login fix failed: $($_.Exception.Message)"
    }

    # Grant logon rights to app pool identity
    # After sysprep + domain rejoin, machine SID changes and these rights are lost.
    # Must be re-granted before IIS/WAS will accept the domain account as app pool identity.
    Write-Log "Granting logon rights to $AdminUser..."
    try {
        Grant-LogonRight $AdminUser "SeBatchLogonRight"
        Write-Log "  SeBatchLogonRight granted"
        Grant-LogonRight $AdminUser "SeServiceLogonRight"
        Write-Log "  SeServiceLogonRight granted"
    } catch {
        Write-Log "  WARNING: logon rights grant failed: $($_.Exception.Message)"
    }

    # Reset app pool identity (machine SID changed after sysprep/rejoin)
    # Must run on every Stage 2 to re-apply credentials after reboot
    Write-Log "Resetting app pool identity to $AdminUser..."
    Import-Module WebAdministration
    Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='$AppPoolName']/processModel" -Name identityType   -Value 3
    Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='$AppPoolName']/processModel" -Name userName       -Value $AdminUser
    Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='$AppPoolName']/processModel" -Name password       -Value $AdminPassword
    Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='$AppPoolName']/processModel" -Name loadUserProfile -Value $true
    Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='$AppPoolName']/failure"      -Name rapidFailProtection -Value $false
    try {
        $appPoolPath = "IIS:\\AppPools\\$AppPoolName"
        Set-ItemProperty $appPoolPath -Name processModel.identityType -Value 3
        Set-ItemProperty $appPoolPath -Name processModel.userName    -Value $AdminUser
        Set-ItemProperty $appPoolPath -Name processModel.password    -Value $AdminPassword
        Set-ItemProperty $appPoolPath -Name processModel.loadUserProfile -Value $true
        Write-Log "App pool identity set to $AdminUser"
    } catch {
        Write-Log "  WARNING: app pool identity reset failed: $($_.Exception.Message)"
    }

    # Start services
    Write-Log "Starting SP services..."
    foreach ($svc in @("AppFabricCachingService","SPTimerV4","SPAdminV4","W3SVC")) {
        try   { Start-Service $svc -ErrorAction Stop; Write-Log "  OK: $svc" }
        catch { Write-Log "  Warn: $svc - $($_.Exception.Message)" }
    }
    Start-Sleep 10

    # Start app pool and site
    Write-Log "Starting app pool and site..."
    Stop-WebAppPool $AppPoolName -ErrorAction SilentlyContinue
    Start-Sleep 3
    Start-WebAppPool $AppPoolName
    Start-Sleep 5
    Start-WebSite "NORCA Intranet" -ErrorAction SilentlyContinue

    # Smoke test (SP cold start can take 2-5 min)
    Write-Log "Smoke test (waiting up to 5 min for SP cold start)..."
    for ($t = 1; $t -le 10; $t++) {
        Start-Sleep 30
        try {
            $response = Invoke-WebRequest -Uri "http://localhost" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 30
            Write-Log "SharePoint HTTP: $($response.StatusCode) -- READY"
            break
        } catch {
            Write-Log "  Not ready yet ($t/10): $($_.Exception.Message)"
        }
    }

    # Register persistent startup recovery task (runs every boot)
    Write-Log "Registering SP-StartupRecovery scheduled task..."
    try {
        $startupCmd = @"
Start-Sleep 60
Import-Module WebAdministration
`$AdminUser     = "$AdminUser"
`$AdminPassword = "$AdminPassword"
`$AppPoolName   = "$AppPoolName"
Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='`$AppPoolName']/processModel" -Name identityType   -Value 3
Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='`$AppPoolName']/processModel" -Name userName       -Value `$AdminUser
Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='`$AppPoolName']/processModel" -Name password       -Value `$AdminPassword
Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='`$AppPoolName']/processModel" -Name loadUserProfile -Value `$true
Set-WebConfigurationProperty -Filter "/system.applicationHost/applicationPools/add[@name='`$AppPoolName']/failure"      -Name rapidFailProtection -Value `$false
foreach (`$svc in @("AppFabricCachingService","SPTimerV4","SPAdminV4","W3SVC")) { Start-Service `$svc -ErrorAction SilentlyContinue }
Stop-WebAppPool `$AppPoolName -ErrorAction SilentlyContinue
Start-Sleep 3
Start-WebAppPool `$AppPoolName
Start-WebSite "NORCA Intranet" -ErrorAction SilentlyContinue
"@
        $action    = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `$startupCmd"
        $trigger   = New-ScheduledTaskTrigger -AtStartup
        $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "SP-StartupRecovery" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
        Write-Log "SP-StartupRecovery registered"
    } catch {
        Write-Log "  WARNING: failed to register SP-StartupRecovery: $($_.Exception.Message)"
    }

    # Cleanup
    Remove-Item $Stage2Flag -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SP01-PostDeploy-Stage2" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "=== STAGE 2 COMPLETE ==="
    exit 0
}

# -- Stage 1: domain rejoin ---------------------------------------------------
Write-Log "=== STAGE 1: Domain rejoin check ==="
$cs = Get-WmiObject Win32_ComputerSystem
Write-Log "PartOfDomain=$($cs.PartOfDomain) Domain=$($cs.Domain)"

if ($cs.PartOfDomain -and $cs.Domain -eq $Domain) {
    Write-Log "Already domain-joined -- jumping to Stage 2."
    New-Item $Stage2Flag -Force | Out-Null
    & $ScriptPath
    exit 0
}

# Wait for DC01 before attempting domain join.
# Azure VM networking + DC boot can take several minutes after first power-on.
Write-Log "Waiting for DC01 ($DcIP) to be reachable (max 10 min)..."
$dcReady = $false
for ($i = 1; $i -le 20; $i++) {
    $dns = Resolve-DnsName $Domain -Server $DcIP -ErrorAction SilentlyContinue
    $tcp = Test-NetConnection -ComputerName $DcIP -Port 389 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($dns -and $tcp.TcpTestSucceeded) {
        Write-Log "DC01 reachable (attempt $i) -- DNS OK, LDAP OK"
        $dcReady = $true
        break
    }
    Write-Log "DC01 not ready ($i/20) -- retrying in 30s..."
    Start-Sleep 30
}
if (-not $dcReady) {
    Write-Log "ERROR: DC01 unreachable after 10 min -- aborting domain join"
    exit 1
}

# Domain join with up to 3 retries
Write-Log "Joining domain $Domain..."
$joined = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Add-Computer -DomainName $Domain -Credential $Cred -Force -ErrorAction Stop
        Write-Log "Domain join succeeded (attempt $attempt)."
        $joined = $true
        break
    } catch {
        Write-Log "Attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -lt 3) { Start-Sleep 15 }
    }
}
if (-not $joined) {
    Write-Log "ERROR: All 3 domain join attempts failed -- exiting"
    exit 1
}

# Schedule Stage 2 to run on next boot (as SYSTEM)
Write-Log "Scheduling Stage 2 post-reboot task..."
New-Item $Stage2Flag -Force | Out-Null
Copy-Item $MyInvocation.MyCommand.Path $ScriptPath -Force

$action    = New-ScheduledTaskAction -Execute "PowerShell.exe" `
               -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "SP01-PostDeploy-Stage2" `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force

Write-Log "Rebooting to complete domain join..."
Start-Sleep 3
Restart-Computer -Force
