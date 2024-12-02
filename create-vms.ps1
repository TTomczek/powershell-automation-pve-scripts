param (
    [string]$serversAndPorts,
    [string]$apiToken,
    [string]$node,
    [string]$iso,
    [int]$vmCount = 1
)

# Parameter abfragen, falls nicht angegeben
if (-not $serversAndPorts) {
	$serversAndPorts = Read-Host -Prompt 'server:port,server:port...'
	if (-not $serversAndPorts) { exit 1 }
}
if (-not $apiToken) { 
	$apiTokenSecure = Read-Host -Prompt 'TokenId=secret' -AsSecureString
	if (-not $apiTokenSecure) { exit 1 }
	$apiToken = (ConvertFrom-SecureString $apiTokenSecure -AsPlainText)
}
if (-not $node) {
	$node = Read-Host -Prompt 'Nodename'
	if (-not $node) { exit 1 }
}
if (-not $iso) {
	$iso = Read-Host -Prompt 'ISO Datei (z.B. local:iso/deine-iso-datei.iso)'
	if (-not $iso) { exit 1 }
}

# Installiere das Modul, falls noch nicht geschehen
if (-not (Get-Module -ListAvailable -Name Corsinvest.ProxmoxVE.Api)) {
	Write-Output "Modul Corsinvest.ProxmoxVE.Api nicht gefunden. Installiere..."
    Install-Module -Name Corsinvest.ProxmoxVE.Api -Scope CurrentUser
}

# Importiere das Modul
Import-Module Corsinvest.ProxmoxVE.Api

# Verbinde dich mit dem Proxmox VE Cluster
$ticket = Connect-PveCluster -HostsAndPorts $serversAndPorts -ApiToken $apiToken -SkipCertificateCheck

$firstUnusedVmId = (Get-PveClusterNextid -PveTicket $ticket).response.data

$result = 1..$vmCount | ForEach-Object -Parallel {
	
	[int]$nextVMID = [int]$using:firstUnusedVmId + [int]$($_)-1
	$vmName = "WebserverVM-$nextVMID"
	
	$sata = @{
		0 = 'local-lvm:32'
	}
	
	$net = @{
		0 = 'virtio,bridge=vmbr0,firewall=1'
	}
	
	$createResult = New-PveNodesQemu -PveTicket $using:ticket -Node $using:node -VMID $nextVMID -Name $vmName -Memory 4096 -Cores 4 -SataN $sata -cdrom $using:iso -NetN $net -Start -Ostype l26 -Agent 1
	if (-not $createResult.IsSuccessStatusCode) {
		Write-Host "Erstellen der VM fehlgeschlagen"
		Write-Host $createResult
		Exit 1
	}
	
    # Warte, bis die VM gestartet ist
	Write-Host "Warte 250 Sekunden auf VM start"
    Start-Sleep -Seconds 250

    # Hole die IP-Adresse der VM
    $vmStatus = Get-PveNodesQemuAgentNetworkGetInterfaces -Node $using:node -VMID $nextVMID -PveTicket $using:ticket
    $vmIP = $vmStatus.response.data.result[1] | Select-Object -ExpandProperty 'ip-addresses' | Select-Object -Property ip-address -ExpandProperty 'ip-address' -First 1
	Write-Host "Virtuelle Maschine mit der ID $nextVMID und dem Namen $vmName wurde erstellt und gestartet. Die IP-Adresse ist: $vmIP"

    return [PSCustomObject]@{
        VMID = $nextVMID
        Name = $vmName
        IPAddress = $vmIP
    }
}
return $result
