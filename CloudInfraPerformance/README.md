# AzureStack Infrastructure performance (snapshot)
AzureStack.Performance module provides simple utilities to capture the snapshot of cloud infrastructure health/performance.

Instructions are relative to the .\CloudInfraPerformance directory.
To run this utility, one needs to be a domain admin and have access to the cluster and the infrastructure VMs

# Download Utility
```powershell
Invoke-WebRequest https://github.com/Azure/AzureStack-Tools/archive/master.zip -OutFile master.zip
Expand-Archive master.zip -DestinationPath . -Force
Set-Location -Path ".\AzureStack-Tools-master\CloudInfraPerformance" -PassThru
```

# Sample usage
```powershell
# Install-Module -Name FailoverClusters -Scope CurrentUser
# To get the point in time overall infrastructure performance snapshot
# Example 1
    $cloudPerf = Get-AzSPerformance -ScaleUnit <Name of the cluster>
    $cloudPerf | Format-Table * 
# Example 2
    $cloudPerf = Get-Cluster -Name <Name of the cluster> | Get-AzSPerformance
    $cloudPerf | Format-Table *

# To get the infrastructure performance snapshot over a sample interval of 60 seconds
# Example 3
    $cloudPerf = Get-AzSPerformance -ScaleUnit <Name of the cluster> -SampleInterval 1 -MaxSamples 60
    $cloudPerf | Format-Table *

# To get the infrastructure performance snapshot and a list of top 3 memory consuming processes from each infrastructure VM
# Example 4
    $cloudPerf, $cloudMemProc = Get-AzSPerformance -ScaleUnit <Name of the cluster> -TopResourceConsumingProcess
    $cloudPerf | Format-Table *
    $cloudMemProc |  Sort-Object "Memory(GB)" -Descending | Format-Table -Wrap
```

