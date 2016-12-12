enum Ensure
{
	Absent
	Present
}

[DscResource()]
class COGITO_xIISSharedConfig
{

	[DscProperty(Key)]
	[string]$Name

	[DscProperty(Mandatory)]
	[Ensure]$Ensure = [Ensure]::Present
	
	[DscProperty(Mandatory)]
	[string]$PhysicalPath
	
	[DscProperty(Mandatory)]
	[PSCredential]$User
	
	[DscProperty(Mandatory)]
	[SecureString]$KeyEncryptionPassword

	[DscProperty()]
	[switch]$DontCopyRemoteKeys

	<#
		This method returns a hashtable with the current IIS shared configuration information, parsed.
	#>
	[Hashtable] GetIISSharedConfig()
	{
		$c = Get-IISSharedConfig
		$c = ConvertFrom-StringData (Get-IISSharedConfig).Replace('\', '\\')
		
		return @{
			Enabled = $c['Enabled'] -eq 'True'
			PhysicalPath = $c['Physical Path']
			UserName = $c['UserName']
		}
	}
	
    <#
        This method is equivalent of the Get-TargetResource script function.
        The implementation should use the keys to find appropriate resources.
        This method returns an instance of this class with the updated key properties.
    #>
	[COGITO_xIISSharedConfig] Get()
	{
		$c = $this.GetIISSharedConfig();

		$this.Ensure = if ($c.Enabled) { [Ensure]::Present } else { [Ensure]::Absent }
		$this.PhysicalPath = $c.PhysicalPath

		return $this
	}

	<#
		Enables the IIS shared configuration.
	#>
	[Hashtable] EnableIISSharedConfig([string]$PhysicalPath, [PSCredential]$User, [SecureString]$KeyEncryptionPassword, [bool]$DontCopyRemoteKeys)
	{
		Enable-IISSharedConfig `
			-PhysicalPath $PhysicalPath `
			-UserName $User.UserName `
			-Password (ConvertTo-SecureString -AsPlainText -Force $User.GetNetworkCredential().Password) `
			-KeyEncryptionPassword $KeyEncryptionPassword

		# return current configuration state
		return $this.GetIISSharedConfig()
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
		}
		
		# return current configuration state
		return $this.GetIISSharedConfig()
	}

	<#
        This method is equivalent of the Set-TargetResource script function.
        It sets the resource to the desired state.
    #>
	[void] Set()
	{
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				$c = $this.GetIISSharedConfig()
				$cEnabled = $c.Enabled
				$cPhysicalPath = $c.PhysicalPath -eq $this.PhysicalPath
				$cUserName = $c.UserName -eq $this.User.UserName

				# check whether any properties are different from current state
				if (!$cEnabled -or !$cPhysicalPath -or !$cUserName) {

					# already enabled, disable first
					if ($cEnabled) {
						$c = $this.DisableIISSharedConfig()
						if ($c.Enabled) {
							New-InvalidOperationException -Message "Could not disable IIS Shared Configuration."
						}
					}

					$c = $this.EnableIISSharedConfig($this.PhysicalPath, $this.User, $this.KeyEncryptionPassword, $this.DontCopyRemoteKeys)
					if (!$c.Enabled) {
						New-InvalidOperationException -Message "Could not enable IIS Shared Configuration."
					}
				}
				
				# check if enabled now
			}

			[Ensure]::Absent {
				$c = $this.GetIISSharedConfig()
				if ($c.Enabled) {
					Write-Verbose 'Disabling IIS Shared Configuration...'
						$c = $this.DisableIISSharedConfig()
					if ($c.Enabled) {
						New-InvalidOperationException -Message "Could not disable IIS Shared Configuration."
					}
				}
			}
		}
	}
	 
	<#
        This method is equivalent of the Test-TargetResource script function.
        It should return True or False, showing whether the resource
        is in a desired state.
    #>
	[bool] Test()
	{
		switch ($this.Ensure)
		{
			[Ensure]::Present {
				$c = $this.GetIISSharedConfig()
				$cEnabled = $c.Enabled
				$cPhysicalPath = $c.PhysicalPath -eq $this.PhysicalPath
				$cUserName = $c.UserName -eq $this.User.UserName

				# check whether any properties are different from current state
				if (!$cEnabled -or !$cPhysicalPath -or !$cUserName) {
					return $false;
				}
			}

			[Ensure]::Absent {
				$c = Get-IISSharedConfig
				return !$c.Enabled
			}
		}

		return $false
	}

}
