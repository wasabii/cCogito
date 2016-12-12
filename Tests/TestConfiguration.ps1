Configuration TestConfiguration
{

	param
	(
		[PSCredential]$UserCredential,
		[SecureString]$KeyEncryptionPassword
	)
    
    Import-DSCResource -ModuleName 'xCogito'

	Node TestNode {
	
		xIISSharedConfig IISSharedConfig
		{
			Name = 'IISSharedConfig'
			Ensure = 'Present'
			PhysicalPath = 'D:\Foo'
			UserCredential = $UserCredential
			KeyEncryptionPassword = $KeyEncryptionPassword
			DontCopyRemoteKeys = $true
		}

	}

}