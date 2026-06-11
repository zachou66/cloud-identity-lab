<#
.SYNOPSIS
    Idempotent, CSV-driven cloud user onboarding for Microsoft Entra ID,
    built on the Microsoft Graph PowerShell SDK. The cloud twin of the
    AD lab's Onboarding.ps1.

.DESCRIPTION
    For each row in users.csv this script:
      - derives a UPN of firstname.lastname@<TenantDomain>
      - checks whether that user already exists (idempotent: skips, never duplicates)
      - creates the user enabled, with a random temp password and forced change
        at first sign-in, and sets UsageLocation / Department / JobTitle
      - adds the user to each group named in RoleGroups (semicolon-separated)
      - logs the whole run via Start-Transcript, with per-user try/catch

    Run it twice with the same CSV to prove idempotency:
      Run 1 -> every row CREATED
      Run 2 -> every row SKIPPED

.PREREQUISITES
    Install-Module Microsoft.Graph -Scope CurrentUser
    A Global Admin (or User Administrator + Groups Administrator) to consent to:
      User.ReadWrite.All, Group.ReadWrite.All

.EXAMPLE
    .\Onboard-CloudUsers.ps1 -CsvPath .\users.csv

.EXAMPLE
    # Capture the transcript for your evidence folder:
    .\Onboard-CloudUsers.ps1 -CsvPath .\users.csv -LogPath .\sample-logs\run1-created.txt

.NOTES
    Author: Zachary Ouldsfiya
    No password is stored in source - each temp password is generated at runtime.
#>

[CmdletBinding()]
param(
    [string] $CsvPath      = (Join-Path $PSScriptRoot 'users.csv'),
    [string] $TenantDomain = 'zaolab.onmicrosoft.com',
    [string] $LogPath      = (Join-Path $PSScriptRoot ("sample-logs\run-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)))
)

# --- Generate a strong random temporary password ----------------------------
function New-TempPassword {
    # 4 character classes, 16 chars, shuffled - meets Entra complexity rules.
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnpqrstuvwxyz',
        '23456789',
        '!@#$%^&*-_'
    )
    $chars = foreach ($s in $sets) { $s[(Get-Random -Maximum $s.Length)] }   # one of each class
    $all = -join $sets
    $chars += 1..12 | ForEach-Object { $all[(Get-Random -Maximum $all.Length)] }
    -join ($chars | Sort-Object { Get-Random })
}

# --- Resolve a group display name to its object id (cached) ------------------
$script:GroupCache = @{}
function Resolve-GroupId {
    param([string] $DisplayName)
    if ($script:GroupCache.ContainsKey($DisplayName)) { return $script:GroupCache[$DisplayName] }
    $group = Get-MgGroup -Filter "displayName eq '$DisplayName'" -All -ErrorAction Stop
    if (-not $group) { throw "Group '$DisplayName' not found - create it before onboarding." }
    if ($group.Count -gt 1) { throw "Group name '$DisplayName' is ambiguous (matched $($group.Count))." }
    $script:GroupCache[$DisplayName] = $group.Id
    return $group.Id
}

# --- Start ------------------------------------------------------------------
$logDir = Split-Path -Parent $LogPath
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Start-Transcript -Path $LogPath -Force | Out-Null

Write-Host "=== Onboard-CloudUsers - $(Get-Date -Format s) ===" -ForegroundColor Cyan
Write-Host "CSV:    $CsvPath"
Write-Host "Tenant: $TenantDomain"
Write-Host ""

try {
    Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All' -NoWelcome -ErrorAction Stop

    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $rows = Import-Csv -Path $CsvPath

    $created = 0; $skipped = 0; $failed = 0

    foreach ($row in $rows) {
        $first = $row.FirstName.Trim()
        $last  = $row.LastName.Trim()
        $upn   = ('{0}.{1}@{2}' -f $first, $last, $TenantDomain).ToLower()
        $display = "$first $last"

        try {
            # --- Idempotency check: does the user already exist? ---
            $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Warning "SKIPPED  $upn - already exists (id $($existing.Id))"
                $skipped++
                continue
            }

            # --- Create the user ---
            $password = New-TempPassword
            $params = @{
                AccountEnabled    = $true
                DisplayName       = $display
                GivenName         = $first
                Surname           = $last
                MailNickname      = ('{0}.{1}' -f $first, $last).ToLower()
                UserPrincipalName = $upn
                UsageLocation     = $row.UsageLocation
                Department        = $row.Department
                JobTitle          = $row.JobTitle
                PasswordProfile   = @{
                    Password                      = $password
                    ForceChangePasswordNextSignIn = $true
                }
            }
            $user = New-MgUser @params -ErrorAction Stop
            Write-Host "CREATED  $upn  (temp password issued, change forced at first sign-in)" -ForegroundColor Green

            # --- Group membership (semicolon-separated RoleGroups) ---
            if ($row.RoleGroups) {
                foreach ($g in ($row.RoleGroups -split ';')) {
                    $name = $g.Trim()
                    if (-not $name) { continue }
                    $gid = Resolve-GroupId -DisplayName $name
                    New-MgGroupMember -GroupId $gid -DirectoryObjectId $user.Id -ErrorAction Stop
                    Write-Host "         + added to $name"
                }
            }
            $created++
        }
        catch {
            Write-Error "FAILED   $upn - $($_.Exception.Message)"
            $failed++
        }
    }

    Write-Host ""
    Write-Host "=== Summary: $created created, $skipped skipped, $failed failed ===" -ForegroundColor Cyan
}
catch {
    Write-Error "Fatal: $($_.Exception.Message)"
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Stop-Transcript | Out-Null
}
