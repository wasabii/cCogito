enum Ensure
{
    Absent
    Present
}

[DscResource()]
class cWaitForFile
{

    [DscProperty(Key)]
    [string]$Path

    [DscProperty(Mandatory)]
    [Ensure]$Ensure

    [DscProperty()]
    [int]$RetryCount = 5

    [DscProperty()]
    [int]$RetryIntervalSec = 60
    
    [cWaitForFile] Get()
    {
        $this.Ensure = if ($this.Test()) { [Ensure]::Present } else { [Ensure]::Absent }
        return $this
    }

    [void] Set()
    {
        if ($this.Ensure -eq [Ensure]::Present)
        {
            for ($i = 0; $i -lt $this.RetryCount; $i++)
            {
                Write-Progress -Activity "Waiting for $($this.Path) to be present..." `
                    -PercentComplete ((100 / $this.RetryCount) * $i) `
                    -CurrentOperation "$($i + 1) / $($this.RetryCount)" `
                    -Status "Attempt"

                if (!(Test-Path $this.Path)) {
                    Start-Sleep -Seconds $this.RetryIntervalSec
                }
            }

            if (!(Test-Path $this.Path)) {
                throw "$($this.Path) not found."
            }
        }

        if ($this.Ensure -eq [Ensure]::Absent)
        {
            for ($i = 0; $i -lt $this.RetryCount; $i++)
            {
                Write-Progress -Activity "Waiting for $($this.Path) to be absent..." `
                    -PercentComplete ((100 / $this.RetryCount) * $i) `
                    -CurrentOperation "$($i + 1) / $($this.RetryCount)" `
                    -Status "Attempt"

                if (Test-Path $this.Path) {
                    Start-Sleep -Seconds $this.RetryIntervalSec
                }
            }

            if (Test-Path $this.Path) {
                throw "$($this.Path) found."
            }
        }
    }
    
    [bool] Test()
    {
        if ($this.Ensure -eq [Ensure]::Present)
        {
            return Test-Path $this.Path
        }

        if ($this.Ensure -eq [Ensure]::Absent)
        {
            return !(Test-Path $this.Path)
        }

        return $false
    }

}

function New-cWaitForFile()
{
    return [cWaitForFile]::new()
}

[DscResource()]
class cChangeDriveLetter
{

    [DscProperty(Key)]
    [string]$DriveLetter

    [DscProperty(Mandatory)]
    [string]$TargetDriveLetter

    [DscProperty()]
    [string]$DriveType = 'CD-ROM'
    
    [cChangeDriveLetter] Get()
    {
        return $this
    }

    [void] Set()
    {
        $a = Get-Volume -DriveLetter $this.DriveLetter -ErrorAction SilentlyContinue
        $b = Get-Volume -DriveLetter $this.TargetDriveLetter -ErrorAction SilentlyContinue
        
        # source exists, target does not exist
        if ($a -and !$b) {

            # drive type specified, validate
            if ($this.DriveType -and $a.DriveType -ne $this.DriveType) {
                return
            }

            # reassign drive letter
            $d = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter = '$($this.DriveLetter):'"
            if ($d) {
                Set-WmiInstance -InputObject $d -Arguments @{ DriveLetter = "$($this.TargetDriveLetter):" }
            }
        }
    }
    
    [bool] Test()
    {
        $a = Get-Volume -DriveLetter $this.DriveLetter -ErrorAction SilentlyContinue
        $b = Get-Volume -DriveLetter $this.TargetDriveLetter -ErrorAction SilentlyContinue

        if ($a -and !$b)
        {
            # no work if drive does not match type
            if ($this.DriveType -and $a.DriveType -ne $this.DriveType) {
                return $true
            }

            # work to be done
            return $false
        }

        return $true
    }

}

function New-cChangeDriveLetter()
{
    return [cChangeDriveLetter]::new()
}

function Get-IISSharedConfigPolyfill()
{
    if (!(Get-Command 'Get-IISSharedConfig' -ErrorAction SilentlyContinue)) {
	Write-Host "Executing polyfill for Get-IISSharedConfig"

        $s = @()
        $c = New-Object Microsoft.IIS.Powershell.Commands.GetIISSharedConfigCommand
        foreach ($p in $c.Invoke()) {
            $s += $p
        }
        return $s
    } else {
        return Get-IISSharedConfig
    }
}

function Enable-IISSharedConfigPolyfill
{
    param(

        [string]$PhysicalPath,
        [string]$UserName,
        [SecureString]$Password,
        [SecureString]$KeyEncryptionPassword,
        [switch]$DontCopyRemoteKeys = $false,
        [switch]$Force = $false
    )

    if (!(Get-Command 'Enable-IISSharedConfig' -ErrorAction SilentlyContinue)) {
	Write-Host "Executing polyfill for Enable-IISSharedConfig"

        $s = @()
        $c = New-Object Microsoft.IIS.Powershell.Commands.EnableIISSharedConfigCommand
        $c.PhysicalPath = $PhysicalPath
        $c.UserName = $UserName
        $c.Password = $Password
        $c.KeyEncryptionPassword = $KeyEncryptionPassword
        $c.DontCopyRemoteKeys = $DontCopyRemoteKeys
        $c.Force = $Force
        foreach ($p in $c.Invoke()) {
            $s += $p
        }
        return $s
    } else {
        return Enable-IISSharedConfig `
            -PhysicalPath $PhysicalPath `
            -UserName $UserName
            -Password $Password
            -KeyEncryptionPassword $KeyEncryptionPassword
            -DontCopyRemoteKeys:$DontCopyRemoteKeys
            -Force:$Force
    }
}

function Disable-IISSharedConfigPolyfill()
{
    if (!(Get-Command 'Disable-IISSharedConfig' -ErrorAction SilentlyContinue)) {
	Write-Host "Executing polyfill for Disable-IISSharedConfig"

        $s = @()
        $c = New-Object Microsoft.IIS.Powershell.Commands.DisableIISSharedConfigCommand
        foreach ($p in $c.Invoke()) {
            $s += $p
        }
        return $s
    } else {
        return Disable-IISSharedConfig
    }
}

[DscResource()]
class cIISSharedConfig
{

    [DscProperty(Key)]
    [string]$Name

    [DscProperty(Mandatory)]
    [Ensure]$Ensure
    
    [DscProperty(Mandatory)]
    [string]$PhysicalPath
    
    [DscProperty()]
    [PSCredential]$UserCredential
    
    [DscProperty(Mandatory)]
    [string]$KeyEncryptionPassword

    [DscProperty()]
    [bool]$DontCopyRemoteKeys = $false

    <#
        This method returns a hashtable with the current IIS shared configuration information.
    #>
    [Hashtable] GetIISSharedConfig()
    {
        $c = ConvertFrom-StringData ((Get-IISSharedConfigPolyfill) -join "`r`n").Replace('\', '\\')
        return @{
            Enabled = $c['Enabled'] -eq 'True'
            PhysicalPath = $c['Physical Path']
            UserName = $c['UserName']
        }
    }

    <#
        Enables the IIS shared configuration.
    #>
    [Hashtable] EnableIISSharedConfig(
        [string]$PhysicalPath, 
        [PSCredential]$UserCredential, 
        [SecureString]$KeyEncryptionPassword, 
        [bool]$DontCopyRemoteKeys)
    {
        if (!($PhysicalPath)) {
            throw 'PhysicalPath required.';
        }

        if (!($KeyEncryptionPassword)) {
            throw 'KeyEncryptionPassword required.';
        }

        $c = $this.GetIISSharedConfig()
        if ($c) {
            Write-Verbose 'Enabling IIS Shared Configuration...'
            if ($UserCredential) {
                Enable-IISSharedConfigPolyfill `
                    -PhysicalPath $PhysicalPath `
                    -UserName $UserCredential.UserName `
                    -Password (ConvertTo-SecureString -AsPlainText -Force $UserCredential.GetNetworkCredential().Password) `
                    -KeyEncryptionPassword $KeyEncryptionPassword `
                    -Force
            } else {
                Enable-IISSharedConfigPolyfill `
                    -PhysicalPath $PhysicalPath `
                    -KeyEncryptionPassword $KeyEncryptionPassword `
                    -Force
            }
            $c = $this.GetIISSharedConfig()
        }

        return $c
    }

    <#
        Disables the IIS shared configuration.
    #>
    [Hashtable] DisableIISSharedConfig()
    {
        $c = $this.GetIISSharedConfig();
        if ($c) {
            Write-Verbose 'Disabling IIS Shared Configuration...'
            Disable-IISSharedConfigPolyfill
            $c = $this.GetIISSharedConfig();
        }
        
        return $c
    }
    
    [cIISSharedConfig] Get()
    {
        $c = $this.GetIISSharedConfig();
        $this.Ensure = if ($c.Enabled) { [Ensure]::Present } else { [Ensure]::Absent }
        $this.PhysicalPath = $c.PhysicalPath
        return $this
    }
    
    [void] Set()
    {
        if ($this.Ensure -eq [Ensure]::Present)
        {
            $c = $this.GetIISSharedConfig()
            $cEnabled = $c.Enabled
            $cPhysicalPath = $c.PhysicalPath -eq $this.PhysicalPath
            $cUserName = if ($this.UserCredential) { $c.UserName -eq $this.UserCredential.UserName } else { [string]::IsNullOrEmpty($c.UserName) }

            # check whether any properties are different from current state
            if (!$cEnabled -or !$cPhysicalPath -or !$cUserName)
            {
                $c = $this.EnableIISSharedConfig(
                    $this.PhysicalPath,
                    $this.UserCredential,
                    (ConvertTo-SecureString -AsPlainText -Force $this.KeyEncryptionPassword),
                    $this.DontCopyRemoteKeys)
                if (!$c.Enabled) {
                    throw "Could not enable IIS Shared Configuration."
                }
            }
        }

        if ($this.Ensure -eq [Ensure]::Absent)
        {
            $c = $this.GetIISSharedConfig()
            if ($c.Enabled) {
                $c = $this.DisableIISSharedConfig()
                if ($c.Enabled) {
                    throw "Could not disable IIS Shared Configuration."
                }
            }
        }
    }
    
    [bool] Test()
    {
        $c = $this.GetIISSharedConfig()

        if ($this.Ensure -eq [Ensure]::Present)
        {
            if ($c.Enabled -ne $true) {
                Write-Verbose "Enabled != True"
                return $false
            }

            if ($c.PhysicalPath -ne $this.PhysicalPath) {
                Write-Verbose "PhysicalPath != $($this.PhysicalPath)"
                return $false
            }

            if ($this.UserCredential) {
                if ($c.UserName -ne $this.UserCredential.UserName) {
                    Write-Verbose "UserName != $($this.UserCredential.UserName)"
                    return $false;
                }
            }
        }

        if ($this.Ensure -eq [Ensure]::Absent)
        {
            if ($c.Enabled -ne $false) {
                Write-Verbose "Enabled != False"
                return $false;
            }
        }

        return $true
    }

}

function New-cIISSharedConfig()
{
    return [cIISSharedConfig]::new()
}