param([string]$LogName = "run.txt")

# auth first (transcript and Connect-MgGraph collide if logging is already running)
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All" -UseDeviceCode

Start-Transcript -Path ".\sample-logs\$LogName"

$users = Import-Csv ".\users.csv"

foreach ($u in $users) {

    $upn = "$($u.FirstName).$($u.LastName)@zaolab.onmicrosoft.com".ToLower()

    # idempotency guard — skip if the user already exists
    if (Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue) {
        Write-Warning "SKIPPED $upn (already exists)"
        continue
    }

    try {
        $pw = -join ((48..57)+(65..90)+(97..122)+(33,35,64) | Get-Random -Count 16 | %{[char]$_})

        $pwProfile = @{
            Password                      = $pw
            ForceChangePasswordNextSignIn = $true
        }

        $newUser = New-MgUser -UserPrincipalName $upn `
            -DisplayName  "$($u.FirstName) $($u.LastName)" `
            -MailNickname "$($u.FirstName).$($u.LastName)".ToLower() `
            -AccountEnabled `
            -PasswordProfile $pwProfile `
            -Department   $u.Department `
            -JobTitle     $u.JobTitle `
            -UsageLocation $u.UsageLocation

        foreach ($g in ($u.RoleGroups -split ';')) {
            $grp = Get-MgGroup -Filter "displayName eq '$($g.Trim())'"
            New-MgGroupMember -GroupId $grp.Id -DirectoryObjectId $newUser.Id
        }

        Write-Host "CREATED $upn"
    }
    catch {
        Write-Warning "FAILED $upn : $_"
    }
}

Stop-Transcript