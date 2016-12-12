. .\TestConfiguration.ps1

TestConfiguration -OutputPath .\TestConfiguration\ -ConfigurationData @{
AllNodes = @(
@{
NodeName = 'TestNode'
PSDscAllowPlainTextPassword = $true
PSDscAllowDomainUser = $true
}
)
}
