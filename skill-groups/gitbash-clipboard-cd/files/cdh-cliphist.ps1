$ErrorActionPreference = "Stop"
[Windows.ApplicationModel.DataTransfer.Clipboard,Windows.ApplicationModel.DataTransfer,ContentType=WindowsRuntime] | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" } | Select-Object -First 1
function Await($op, $t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
$res = Await ([Windows.ApplicationModel.DataTransfer.Clipboard]::GetHistoryItemsAsync()) ([Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResult])
foreach ($it in $res.Items) {
  try {
    $txt = Await ($it.Content.GetTextAsync()) ([string])
    if (-not $txt) { continue }
    $c = $txt.Trim().Trim('"')
    if ($c -match "[\r\n]") { continue }
    if (Test-Path -LiteralPath $c -PathType Container) { [Console]::Out.Write($c); exit 0 }
  } catch {}
}
exit 1
