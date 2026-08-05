param([Parameter(Mandatory=$true)][string]$JobDir)

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AnimePowerState {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@

$ES_CONTINUOUS = [uint32]0x80000000
$ES_SYSTEM_REQUIRED = [uint32]0x00000001
$statusFile = Join-Path $JobDir 'status.txt'

try {
    while ($true) {
        [void][AnimePowerState]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
        if (Test-Path -LiteralPath $statusFile) {
            $status = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8
            if ($status.StartsWith('DONE|') -or $status.StartsWith('ERROR|')) { break }
        }
        Start-Sleep -Seconds 20
    }
} finally {
    [void][AnimePowerState]::SetThreadExecutionState($ES_CONTINUOUS)
}
