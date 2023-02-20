Param (
	  [Parameter(Mandatory=$false)] 
    [string] $MachineIp = "***.***.***.***",

    [Parameter(Mandatory=$false)] 
    [string] $CredentialName = "CredentailName",
    
    [Parameter(Mandatory=$false)] 
    [string] $KeyVaultName = "KeyVaultName",
    
    [Parameter(Mandatory=$false)] 
    [string] $KeyName = "KeyName"
)
Write-Output 'Connecting Az Account'
Connect-AzAccount -Identity


Write-Output "Getting credentials…"
$cred = Get-AutomationPSCredential -Name $CredentialName
$username = $cred.GetNetworkCredential().Username
$password = $cred.Password
$keyVal = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyName -AsPlainText
$privateKey = "-----BEGIN RSA PRIVATE KEY-----`n" + $keyVal.Replace(" ", "`n") + "`n-----END RSA PRIVATE KEY-----"
$nopasswd = new-object System.Security.SecureString
$Credential = New-Object System.Management.Automation.PSCredential ("$username", $nopasswd)

[int]$Retry = "0"
$Stoploop = $false
do {
	try {

			Write-Output "Openning ssh session…"
			$Session = New-SSHSession -ComputerName $MachineIp -KeyString $privateKey -Credential $Credential -AcceptKey -ConnectionTimeout 60
			$Stream = $Session.Session.CreateShellStream("PS-SSH", 0, 0, 0, 0, 1024)

			Write-Output "Invoking command…"
			Invoke-SSHStreamShellCommand -ShellStream $Stream -Command "cd taiga-docker"
			do {
				Invoke-SSHStreamExpectSecureAction -ShellStream $Stream -Command "sudo sh launch-all.sh" -ExpectString "[sudo] password for ${$Name}:" -SecureAction $password -Verbose
				Start-Sleep -Seconds 5
				$Stream.WriteLine("whoami")
				$output = $Stream.read()
				Write-Output $output
			} while(!($output -match '${$Name}'))

			Start-Sleep -Seconds 5
			Invoke-SSHStreamExpectSecureAction -ShellStream $Stream -Command "sudo sh launch-all.sh" -ExpectString "[sudo] password for ${$Name}:" -SecureAction $password -Verbose
			$Stream.read()

            $Stoploop = $true
            echo "The runbook had to retry $Retry times"
        }
        catch {
            if ($Retry -gt 30) {
                echo "Azure service failed to respond after 30 retries"
                $Stoploop = $true
            } else {
                echo "Azure service non-responsive. Retrying in 10 sec ($Retry)"
                Start-Sleep -Seconds 10
				Remove-SSHSession -SSHSession $Session
                $Retry++
            }
        }
} While ($Stoploop -eq $false)

Remove-SSHSession -SSHSession $Session
