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
		$a = Get-Volume -DriveLetter $this.DriveLetter
		$b = Get-Volume -DriveLetter $this.TargetDriveLetter
		
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
		$a = Get-Volume -DriveLetter $this.DriveLetter
		$b = Get-Volume -DriveLetter $this.TargetDriveLetter

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

[DscResource()]
class cIISSharedConfig
{

	[DscProperty(Key)]
	[string]$Name

	[DscProperty(Mandatory)]
	[Ensure]$Ensure
	
	[DscProperty(Mandatory)]
	[string]$PhysicalPath
	
	[DscProperty(Mandatory)]
	[PSCredential]$UserCredential
	
	[DscProperty(Mandatory)]
	[PSCredential]$KeyEncryptionPassword

	[DscProperty()]
	[bool]$DontCopyRemoteKeys = $false

	<#
		This method returns a hashtable with the current IIS shared configuration information, parsed.
	#>
	[Hashtable] GetIISSharedConfig()
	{
		$c = ConvertFrom-StringData ((Get-IISSharedConfig) -join "`r`n").Replace('\', '\\')
		
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

        if (!($UserCredential)) {
            throw 'UserCredential required.';
        }

        if (!($KeyEncryptionPassword)) {
            throw 'KeyEncryptionPassword required.';
        }

		$c = $this.GetIISSharedConfig()
		if ($c) {
			Write-Verbose 'Enabling IIS Shared Configuration...'
			Enable-IISSharedConfig `
				-PhysicalPath $PhysicalPath `
				-UserName $UserCredential.UserName `
				-Password (ConvertTo-SecureString -AsPlainText -Force $UserCredential.GetNetworkCredential().Password) `
				-KeyEncryptionPassword $KeyEncryptionPassword `
				-Force
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
			Disable-IISSharedConfig
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
			$cUserName = $c.UserName -eq $this.UserCredential.UserName

			# check whether any properties are different from current state
			if (!$cEnabled -or !$cPhysicalPath -or !$cUserName)
			{
				$c = $this.EnableIISSharedConfig(
					$this.PhysicalPath, 
					$this.UserCredential, 
					(ConvertTo-SecureString -AsPlainText -Force $this.KeyEncryptionPassword.GetNetworkCredential().Password),
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

			if ($c.UserName -ne $this.UserCredential.UserName) {
				Write-Verbose "UserName != $($this.UserCredential.UserName)"
				return $false;
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

[DscResource()]
class cDfsrMember
{

    [DscProperty(Mandatory)]
    [Ensure]$Ensure

    [DscProperty(Key)]
    [string]$GroupName

    [DscProperty(Mandatory)]
    [string]$InvokeOnComputerName

    [DscProperty()]
    [PSCredential]$Credential

	<#
		Executes the command on the remote management computer.
	#>
    [object] Invoke($ScriptBlock)
    {
        return Invoke-Command -ComputerName $this.InvokeOnComputerName -Credential $this.Credential -ScriptBlock $ScriptBlock
    }

	<#
		Gets the DFSR member object.
	#>
    [object] GetDfsrMember()
    {
        $c = $env:COMPUTERNAME
        $d = (Get-ADDomain).DNSRoot
        return $this.Invoke({ Get-DfsrMember -DomainName $d -GroupName $this.GroupName -ComputerName $c })
    }

    [cDfsrMember] Get()
    {
        $m = $this.GetDfsrMember()
        $this.Ensure = if ($m) { [Ensure]::Present } else { [Ensure]::Absent }
        return $this
    }

    [bool] Test()
    {
        $m = $this.GetDfsrMember()
        if ($m) {
            return $true
        } else {
            return $false
        }
    }

    [void] Set()
    {
        if (!$this.Test()) {
            $c = $env:COMPUTERNAME
            $d = (Get-ADDomain).DNSRoot

            $this.Invoke({
                $m = Get-DfsrMember -DomainName $d -GroupName $this.GroupName -ComputerName $c
                if (!$m) {
                    Add-DfsrMember -DomainName $d -GroupName $this.GroupName -ComputerName $c
                } else {
                    
                }
            })
        }
    }

}

function New-cDfsrMember()
{
	return [cDfsrMember]::new()
}