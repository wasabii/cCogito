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
	[Ensure]$Ensure = [Ensure]::Present

	[DscProperty()]
	[int]$RetryCount = 5

	[DscProperty()]
	[int]$RetryIntervalSec = 60
	
	[cWaitForFile] Get()
	{
		$this.Ensure = $this.Test()
		return $this
	}

	[void] Set()
	{
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				for ($i = 0; $i -lt $this.RetryCount; $i++)
				{
					if (!(Test-Path $this.Path)) {
						Write-Verbose "$this.Path not found, waiting..."
						Start-Sleep -Seconds $this.RetryIntervalSec
					}
				}

				if (!(Test-Path $this.Path)) {
					New-InvalidOperationException -Message "$this.Path not found. Permanent failure."
				}
			}

			[Ensure]::Absent {
				for ($i = 0; $i -lt $this.RetryCount; $i++)
				{
					if (Test-Path $this.Path) {
						Write-Verbose "$this.Path found, waiting..."
						Start-Sleep -Seconds $this.RetryIntervalSec
					}
				}

				if (Test-Path $this.Path) {
					New-InvalidOperationException -Message "$this.Path found. Permanent failure."
				}
			}
		}
	}
	
	[bool] Test()
	{
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				return Test-Path $this.Path
			}

			[Ensure]::Absent {
				return !Test-Path $this.Path
			}
		}

		return $false
	}

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

		if ($a -and !$b) {

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

[DscResource()]
class cIISSharedConfig
{

	[DscProperty(Key)]
	[string]$Name

	[DscProperty(Mandatory)]
	[Ensure]$Ensure = [Ensure]::Present
	
	[DscProperty(Mandatory)]
	[string]$PhysicalPath
	
	[DscProperty(Mandatory)]
	[PSCredential]$UserCredential
	
	[DscProperty(Mandatory)]
	[string]$KeyEncryptionPassword

	[DscProperty()]
	[bool]$DontCopyRemoteKeys = $false

	<#
		This method returns a hashtable with the current IIS shared configuration information, parsed.
	#>
	[Hashtable] GetIISSharedConfig()
	{
		$c = ConvertFrom-StringData (Get-IISSharedConfig).Replace('\', '\\')
		
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
		[string]$KeyEncryptionPassword, 
		[bool]$DontCopyRemoteKeys)
	{
		$c = $this.GetIISSharedConfig()
		if ($c) {
			Write-Verbose 'Enabling IIS Shared Configuration...'
			Enable-IISSharedConfig `
				-PhysicalPath $PhysicalPath `
				-UserName $UserCredential.UserName `
				-Password (ConvertTo-SecureString -AsPlainText -Force $UserCredential.GetNetworkCredential().Password) `
				-KeyEncryptionPassword (ConvertTo-SecureString -AsPlainText -Force $KeyEncryptionPassword)
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
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				$c = $this.GetIISSharedConfig()
				$cEnabled = $c.Enabled
				$cPhysicalPath = $c.PhysicalPath -eq $this.PhysicalPath
				$cUserName = $c.UserName -eq $this.UserCredential.UserName

				# check whether any properties are different from current state
				if (!$cEnabled -or !$cPhysicalPath -or !$cUserName) {

					# already enabled, disable first
					if ($cEnabled) {
						$c = $this.DisableIISSharedConfig()
						if ($c.Enabled) {
							New-InvalidOperationException -Message "Could not disable IIS Shared Configuration."
						}
					}

					$c = $this.EnableIISSharedConfig($this.PhysicalPath, $this.UserCredential, $this.KeyEncryptionPassword, $this.DontCopyRemoteKeys)
					if (!$c.Enabled) {
						New-InvalidOperationException -Message "Could not enable IIS Shared Configuration."
					}
				}
			}

			[Ensure]::Absent {
				$c = $this.GetIISSharedConfig()
				if ($c.Enabled) {
					$c = $this.DisableIISSharedConfig()
					if ($c.Enabled) {
						New-InvalidOperationException -Message "Could not disable IIS Shared Configuration."
					}
				}
			}
		}
	}
	
	[bool] Test()
	{
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				$c = $this.GetIISSharedConfig()
				$cEnabled = $c.Enabled
				$cPhysicalPath = $c.PhysicalPath -eq $this.PhysicalPath
				$cUserName = $c.UserName -eq $this.UserCredential.UserName

				# check whether any properties are different from current state
				if (!$cEnabled -or !$cPhysicalPath -or !$cUserName) {
					return $false;
				}
			}

			[Ensure]::Absent {
				$c = $this.GetIISSharedConfig()
				return !$c.Enabled
			}
		}

		return $false
	}

}
