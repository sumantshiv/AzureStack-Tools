function Get-AzSPerformance
{
    [CmdletBinding(DefaultParameterSetName="default")]
    param (    
        [parameter(HelpMessage="Name of your AzureStack cluster")]
        [Parameter(ParameterSetName="default", 
                   Mandatory=$true, 
                   Position = 0, 
                   ValueFromPipeline=$true, 
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$ScaleUnit,

        [parameter(HelpMessage="Performance counter interval (between samples) size in seconds")]
        [Parameter(ParameterSetName="default", 
                   Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [int]$SampleInterval = 1,

        [parameter(HelpMessage="Maximum number of samples to be collected")]
        [Parameter(ParameterSetName="default", 
                   Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [int]$MaxSamples = 1,

        [parameter(HelpMessage="Switch to show the top memory consuming processes from the infrastructure VMs")]
        [Parameter(ParameterSetName="default", 
                   Mandatory=$false)]
        [switch]$TopResourceConsumingProcess
    )

    function Get-CounterValue
    {
        param (   
            $CounterValues,
            [string]$CounterName,
            [string]$ComputerName
        ) 

        $intCtr = $CounterValues | Where-Object {$_.Path -match $ComputerName}
        $ctrName = "*$CounterName*"
        ($intCtr | Where-Object {$_.Path -like $ctrName}).CookedValue
    }

    function Get-ComputerUptime
    {
        param (
            $CurrentTime,
            [string]$ComputerName
        )
        
        $osClass = Get-WmiObject win32_operatingsystem -ComputerName $ComputerName
        $upTime = $CurrentTime - ($osClass.ConvertToDateTime($osClass.lastbootuptime))
        $upTime
    }

    $cluster = $ScaleUnit
    $countersHash = @{"VMCPU(%)"            = "\Processor(_total)\% processor time"; 
                      "Commit(GB)"          = "\Memory\committed bytes";
                      "CommitUse(%)"        = "\Memory\% committed bytes in use";
                      "NIC(MB/s)"           = "\Network Interface(*)\bytes total/sec";
                      "DiskR(GB/s)"         = "\physicaldisk(_total)\disk read bytes/sec";
                      "DiskR(IOPS)"         = "\physicaldisk(_total)\disk reads/sec";
                      "RLatency(ms)"        = "\physicaldisk(_total)\avg. disk sec/read";
                      "RQD"                 = "\physicaldisk(_total)\avg. disk read queue length";
                      "DiskW(GB/s)"         = "\physicaldisk(_total)\disk write bytes/sec";
                      "DiskW(IOPS)"         = "\physicaldisk(_total)\disk writes/sec";
                      "WLatency(ms)"        = "\physicaldisk(_total)\avg. disk sec/write";
                      "WQD"                 = "\physicaldisk(_total)\avg. disk write queue length";
                      "HostCPU(%)"          = "\Hyper-V Hypervisor Logical Processor(_total)\% Total Run Time"}
    $countersList = $countersHash.Values -as [System.Object[]]

    try 
    {
        Get-Cluster -Name $cluster -ErrorAction Stop | Out-Null
    }
    catch 
    {
        throw "Cluster not found or unreachable. `n$_.Exception.Message"           
    }

    try
    {
        $clusterNodes = (Get-ClusterNode -Cluster $cluster -ErrorAction Stop).Name
    }
    catch
    {
        throw "Cluster nodes could not be retrieved. `n$_.Exception.Message"        
    }

    try
    {
        $infraVM = Invoke-Command (Get-ClusterNode -Cluster $cluster -ErrorAction Stop) -Script{(Get-VM).VMName}
    }
    catch
    {
        throw "Infrastructure VMs could not be retrieved. `n$_.Exception.Message"        
    }
    $infVM = @()
    foreach ($iVM in $infraVM)
    {
        try
        {           
            [System.Guid]::Parse($iVM) | Out-Null
        }
        catch
        {
            $infVM += $iVM 
        }
    }

    try
    {
        $vmSettings = Invoke-Command (Get-ClusterNode -Cluster $cluster -ErrorAction Stop) -Script{Get-VM | Select-Object Name, MemoryStartup, ProcessorCount, ComputerName}
    }
    catch
    {
        throw "Unable to retrieve the virtual machine settings. `n$_.Exception.Message"        
    }

    if ($TopResourceConsumingProcess)
    {   
        $infraProcessJob = Start-Job { 
            try 
            {           
                $procSummaryTable = @()          
                for ($iVM = 0; $iVM -lt ($using:infVM).Count; $iVM++)
                {                           
                    $procSummary = Invoke-Command -ComputerName ($using:infVM)[$iVM] -Script{Get-Process | Sort-Object -Property PrivateMemorySize -Descending | Select-Object -First 3 | Select-Object ProcessName, PrivateMemorySize, CPU, Path}          
                    foreach ($proc in $procSummary)
                    {           
                        $pSummary = New-Object -TypeName psobject
                        $pSummary | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "ComputerName" -Value ($using:infVM)[$iVM]
                        $pSummary | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "ProcessName"  -Value $proc.ProcessName
                        $pSummary | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "Memory(GB)"   -Value ([math]::Round((($proc.PrivateMemorySize)/1GB), 2))
                        $pSummary | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "ProcessPath"  -Value $proc.Path
                        $procSummaryTable += $pSummary
                    }                       
                }  
                $procSummaryTable 
            }
            catch 
            {
                throw "Failed to retrieve the process details. `n$_.Exception.Message"        
            }             
        }
    }
    $allMachines = $infVM + $clusterNodes
    $counterValues = (Get-Counter -Counter $countersList -ComputerName $allMachines -SampleInterval $SampleInterval -MaxSamples $MaxSamples -ErrorAction SilentlyContinue).CounterSamples

    $counterTable = @()
    $currTime = Get-Date
    foreach ($machine in $allMachines)
    {
        $counterDetails = New-Object -TypeName psobject
        $upTime = Get-ComputerUptime -CurrentTime $currTime -ComputerName $machine
        $upT = "{0:dd}.{0:hh}:{0:mm}:{0:ss}" -f $upTime

        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "ComputerName"  -Value $machine
        if ($infraVM.Contains($machine))
        {
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "Cores"     -Value (($vmSettings | Where-Object Name -like $machine).ProcessorCount)
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "CPU(%)"    -Value ([math]::Round((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("VMCPU(%)") -ComputerName $machine | Measure-Object -Average).Average, 2))
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "RAM(GB)"   -Value (($vmSettings | Where-Object Name -like $machine).MemoryStartup/1GB)
        }
        if ($clusterNodes.Contains($machine))
        {
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "Cores"     -Value (((Get-WmiObject -Class Win32_processor -ComputerName $machine -ErrorAction SilentlyContinue).NumberOfCores | Measure-Object -Sum).Sum)
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "CPU(%)"    -Value ([math]::Round((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("HostCPU(%)") -ComputerName $machine | Measure-Object -Average).Average, 2))
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "RAM(GB)"   -Value (((Get-WmiObject -Class Win32_PhysicalMemory -ComputerName $machine -ErrorAction SilentlyContinue).Capacity | Measure-Object -Sum).Sum/1GB)
        }
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "Commit(GB)"    -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("Commit(GB)") -ComputerName $machine | Measure-Object -Average).Average)/1GB, 2))        
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "CommitUse(%)"  -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("CommitUse(%)") -ComputerName $machine | Measure-Object -Average).Average), 2))                
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "NIC(MB/s)"     -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("NIC(MB/s)") -ComputerName $machine | Measure-Object -Average).Average/1MB), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "DiskR(GB/s)"   -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("DiskR(GB/s)") -ComputerName $machine | Measure-Object -Average).Average/1GB), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "DiskR(IOPS)"   -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("DiskR(IOPS)") -ComputerName $machine | Measure-Object -Average).Average), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "RLatency(ms)"  -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("RLatency(ms)") -ComputerName $machine | Measure-Object -Average).Average*1000), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "RQD"           -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("RQD") -ComputerName $machine | Measure-Object -Average).Average), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "DiskW(GB/s)"   -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("DiskW(GB/s)") -ComputerName $machine | Measure-Object -Average).Average/1GB), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "DiskW(IOPS)"   -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("DiskW(IOPS)") -ComputerName $machine | Measure-Object -Average).Average), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "WLatency(ms)"  -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("WLatency(ms)") -ComputerName $machine | Measure-Object -Average).Average*1000), 2))
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "WQD"           -Value ([math]::Round(((Get-CounterValue -CounterValues $counterValues -CounterName $countersHash.Get_Item("WQD") -ComputerName $machine | Measure-Object -Average).Average), 2))
        
        $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "Uptime"        -Value $upT
        if ($infraVM.Contains($machine))
        {
            $counterDetails | Add-Member -Type NoteProperty -TypeName System.Management.Automation.PSCustomObject -Name "ScaleUnitNode" -Value (($vmSettings | Where-Object Name -like $machine).ComputerName)
        }
        $counterTable += $counterDetails
    }

    if ((-not $TopResourceConsumingProcess))
    {
        $counterTable
    }
    else
    {
        $infraProcesses = $infraProcessJob | Receive-Job -Wait
        $infraProcessJob | Remove-Job -Force

        $counterTable, $infraProcesses
    }

}

Export-ModuleMember -Function Get-AzSPerformance -Alias GAzSPerf