# Stand-ins for commands that do not exist on the test machine (the ActiveDirectory
# module needs RSAT and a domain; CIM needs Windows). Pester can only mock a command
# that exists, so these empty definitions give it something to replace. Every test
# mocks them; they are never really called.

$stubs = [ordered]@{
    'Get-ADUser'           = '[CmdletBinding()] param($Identity, $Filter, $Properties, $SearchBase)'
    'Get-ADComputer'       = '[CmdletBinding()] param($Identity, $Filter, $Properties, $SearchBase)'
    'New-ADUser'           = '[CmdletBinding(SupportsShouldProcess)] param($Name, $GivenName, $Surname, $DisplayName, $SamAccountName, $UserPrincipalName, $Path, $Department, $Title, $Office, $AccountPassword, $ChangePasswordAtLogon, $Enabled)'
    'Add-ADGroupMember'    = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $Members)'
    'Remove-ADGroupMember' = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $Members)'
    'Disable-ADAccount'    = '[CmdletBinding(SupportsShouldProcess)] param($Identity)'
    'Set-ADUser'           = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $Description)'
    'Move-ADObject'        = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $TargetPath)'
    'Get-CimInstance'      = '[CmdletBinding()] param($ClassName, $Filter, $ComputerName)'
}

foreach ($name in $stubs.Keys) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
        $definition = [scriptblock]::Create($stubs[$name] + ' throw "stub called: not mocked" ')
        Set-Item -Path "function:global:$name" -Value $definition
    }
}
