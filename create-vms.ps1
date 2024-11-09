param (
    [string]$servers,
    [string]$apiToken,
    [string]$node,
    [string]$iso,
    [int]$vmCount = 1
)

# Installiere das Modul, falls noch nicht geschehen
if (-not (Get-Module -ListAvailable -Name Corsinvest.ProxmoxVE.Api)) {
	Write-Output "Modul Corsinvest.ProxmoxVE.Api nicht gefunden. Installiere..."
    Install-Module -Name Corsinvest.ProxmoxVE.Api -Scope CurrentUser
}

# Importiere das Modul
Import-Module Corsinvest.ProxmoxVE.Api

# Parameter abfragen, falls nicht angegeben
if (-not $servers) { $servers = Read-Host -Prompt 'server:port,server:port...' }
if (-not $apiToken) { $user = Read-Host -Prompt 'TokenId=secret' }
if (-not $node) { $node = Read-Host -Prompt 'Nodename' }
if (-not $iso) { $iso = Read-Host -Prompt 'ISO Datei (z.B. local:iso/deine-iso-datei.iso)' }

# Verbinde dich mit dem Proxmox VE Cluster
$ticket = Connect-PveCluster -HostsAndPorts $servers -ApiToken $apiToken -SkipCertificateCheck

$firstUnusedVmId(Get-PveClusterNextid -PveTicket $using:ticket).response.data

1..$vmCount | ForEach-Object -Parallel {
	
	$nextVMID = $using:firstUnusedVmId + $($_)
	$vmName = "WebserverVM-$nextVMID"
	
	$sata = @{
		0 = 'local-lvm:32'
	}
	
	$net = @{
		0 = 'virtio,bridge=vmbr0;firewall=1'
	}
	
	$createdVm = New-PveNodesQemu -PveTicket $using:ticket -Node $using:node -VMID $nextVMID -Name $vmName -Memory 4096 -Cores 4 -SataN $sata -cdrom $using:iso -NetN $net -Start -Ostype l26
	
    # Warte, bis die VM gestartet ist
	Write-Output "Warte 240 Sekunden auf VM start"
    Start-Sleep -Seconds 240

    # Hole die IP-Adresse der VM
    $vmStatus = Get-PveNodesQemuConfig -Node $using:node -VMID $nextVMID -PveTicket ticket -Current true
    $vmIP = $vmStatus.Network | Where-Object { $_.name -eq 'net0' } | Select-Object -ExpandProperty 'ip-addresses'

    return [PSCustomObject]@{
        VMID = $VMID
        Name = $Name
        IPAddress = $vmIP[0]
    }
}

# Ausgabe der Ergebnisse
$results | ForEach-Object {
    Write-Host "Virtuelle Maschine mit der ID $($_.VMID) und dem Namen $($_.Name) wurde erstellt und gestartet."
    Write-Host "Die IP-Adresse der VM ist: $($_.IPAddress)"
}
