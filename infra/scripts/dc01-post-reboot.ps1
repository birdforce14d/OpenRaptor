# =============================================================================
# Module-01: DC01 Post-Reboot Script (Part 2)
# Runs automatically via RunOnce after AD DS promotion reboot
# Creates: OUs, service accounts, employee accounts, DNS records, GPO
# Note: All accounts use Norca@2024! as the standard lab password.
# Employee background accounts intentionally share this password for lab simplicity.
# =============================================================================

#Requires -RunAsAdministrator
Import-Module ActiveDirectory
$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\dc01-post-reboot.log" -Append -Force

$DomainDN  = "DC=norca,DC=click"
$SvcPass   = ConvertTo-SecureString "Norca@2024!" -AsPlainText -Force
$StudPass  = ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force

Write-Host "[1/6] Creating OUs..."
$OUs = @("Employees","ServiceAccounts","Computers","Groups")
foreach ($ou in $OUs) {
    try { New-ADOrganizationalUnit -Name $ou -Path $DomainDN -ProtectedFromAccidentalDeletion $false } catch { Write-Host ("OU ${ou} already exists") }
}

Write-Host "[2/6] Creating service accounts..."
$SvcAccounts = @(
    @{ Name="svc-sp-farm"; DisplayName="SharePoint Farm Service";  OU="ServiceAccounts" },
    @{ Name="svc-sp-app";  DisplayName="SharePoint App Pool";      OU="ServiceAccounts" }
)
foreach ($acct in $SvcAccounts) {
    try {
        New-ADUser `
            -Name $acct.DisplayName `
            -SamAccountName $acct.Name `
            -UserPrincipalName "$($acct.Name)@norca.click" `
            -AccountPassword $SvcPass `
            -PasswordNeverExpires $true `
            -Enabled $true `
            -Path "OU=$($acct.OU),$DomainDN"
    } catch { Write-Host ("Service account " + $acct.Name + " already exists") }
}

Write-Host "[3/6] Creating student/scenario accounts..."
$Students = @(
    @{ Name="cirtstudent"; Display="CIRT Student";   Pass=$StudPass },
    @{ Name="j.chen";      Display="Jennifer Chen";  Pass=$StudPass }
)
foreach ($s in $Students) {
    try {
        New-ADUser `
            -Name $s.Display `
            -SamAccountName $s.Name `
            -UserPrincipalName "$($s.Name)@norca.click" `
            -AccountPassword $s.Pass `
            -PasswordNeverExpires $true `
            -Enabled $true `
            -Path "OU=Employees,$DomainDN"
    } catch { Write-Host ("User " + $s.Name + " already exists") }
}

Write-Host "[4/6] Creating employee background accounts..."
$Employees = @(
    @{ First="Sarah";  Last="Chen";     Sam="s.chen";      Title="IT Administrator" },
    @{ First="James";  Last="Wilson";   Sam="j.wilson";    Title="Finance Manager" },
    @{ First="Priya";  Last="Patel";    Sam="p.patel";     Title="HR Manager" },
    @{ First="Tom";    Last="OBrien";   Sam="t.obrien";    Title="Developer" },
    @{ First="Mei";    Last="Lin";      Sam="m.lin";       Title="Marketing" },
    @{ First="David";  Last="Kumar";    Sam="d.kumar";     Title="Sales" },
    @{ First="Lisa";   Last="Thompson"; Sam="l.thompson";  Title="Legal" },
    @{ First="Ahmed";  Last="Hassan";   Sam="a.hassan";    Title="IT Support" }
)
foreach ($emp in $Employees) {
    try {
        New-ADUser `
            -GivenName $emp.First `
            -Surname $emp.Last `
            -Name "$($emp.First) $($emp.Last)" `
            -SamAccountName $emp.Sam `
            -UserPrincipalName "$($emp.Sam)@norca.click" `
            -Title $emp.Title `
            -AccountPassword $SvcPass `
            -PasswordNeverExpires $true `
            -Enabled $true `
            -Path "OU=Employees,$DomainDN"
    } catch { Write-Host ("Employee " + $emp.Sam + " already exists") }
}

Write-Host "[5/6] Creating DNS A records..."
try { Add-DnsServerResourceRecordA -ZoneName "norca.click" -Name "dc01"         -IPv4Address "10.10.1.10" } catch {}
try { Add-DnsServerResourceRecordA -ZoneName "norca.click" -Name "sharepoint"   -IPv4Address "10.10.3.10" } catch {}
try { Add-DnsServerResourceRecordA -ZoneName "norca.click" -Name "win-norca-sp01" -IPv4Address "10.10.3.10" } catch {}

Write-Host "[6/6] Creating Audit Policy GPO..."
try {
    $GPO = New-GPO -Name "NORCA-Audit-Policy"
    Set-GPRegistryValue -Name "NORCA-Audit-Policy" `
        -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit" `
        -ValueName "ProcessCreationIncludeCmdLine_Enabled" `
        -Type DWord -Value 1
    New-GPLink -Name "NORCA-Audit-Policy" -Target $DomainDN
} catch { Write-Host "GPO already exists or failed: $_" }

Write-Host "`n[DONE] DC01 configuration complete."
Write-Host "Domain: norca.click | Users created | DNS records set | GPO linked"
Stop-Transcript
