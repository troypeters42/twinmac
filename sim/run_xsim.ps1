[CmdletBinding()]
param (
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
  [string]$Testbench,

  [Parameter(Mandatory = $true, Position = 1)]
  [ValidateNotNullOrEmpty()]
  [string[]]$Sources,

  [string]$VivadoBin = 'C:\Xilinx\Vivado\2024.2\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runLog = $null

function Invoke-XsimTool {
  param (
    [string]$Executable,
    [string[]]$ToolArguments,
    [string]$LogPath
  )

  $toolPath = Join-Path $VivadoBin ($Executable + '.bat')
  $commandLine = '> ' + $toolPath + ' ' + ($ToolArguments -join ' ')
  Write-Host $commandLine
  Add-Content -LiteralPath $LogPath -Value $commandLine -Encoding ASCII
  $toolLines = @(& $toolPath @ToolArguments 2>&1 | ForEach-Object { $_.ToString() })
  $toolExitCode = $LASTEXITCODE
  if ($toolLines.Count -gt 0) {
    Add-Content -LiteralPath $LogPath -Value $toolLines -Encoding ASCII
    $toolLines | ForEach-Object { Write-Host $_ }
  }
  if ($toolExitCode -ne 0) {
    throw "$Executable exited with code $toolExitCode. See $LogPath"
  }
  if ($toolLines -match 'FAILED|^\s*(ERROR|FATAL)\s*[:\[]') {
    throw "$Executable reported a failure or error. See $LogPath"
  }
  return $toolLines
}

try {
  $repositoryRoot = Split-Path -Parent $PSScriptRoot
  if ((Get-Location).Path -ne $repositoryRoot) {
    throw "Run this script from the repository root: $repositoryRoot"
  }
  foreach ($sourcePath in $Sources) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
      throw "Source file not found: $sourcePath"
    }
  }
  foreach ($executable in @('xvlog', 'xelab', 'xsim')) {
    $executablePath = Join-Path $VivadoBin ($executable + '.bat')
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
      throw "Required simulator tool not found: $executablePath"
    }
  }

  $logDirectory = Join-Path $PSScriptRoot 'logs'
  New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
  $runLog = Join-Path $logDirectory ($Testbench + '.run.log')
  Set-Content -LiteralPath $runLog -Value "Testbench: $Testbench" -Encoding ASCII
  $snapshot = $Testbench + '_sim'

  $compileArguments = @('-sv') + $Sources + @(
    '-log', (Join-Path $logDirectory ($Testbench + '.xvlog.log'))
  )
  $null = Invoke-XsimTool -Executable 'xvlog' -ToolArguments $compileArguments `
    -LogPath $runLog

  $elaborateArguments = @(
    $Testbench, '-s', $snapshot,
    '-log', (Join-Path $logDirectory ($Testbench + '.xelab.log'))
  )
  $null = Invoke-XsimTool -Executable 'xelab' -ToolArguments $elaborateArguments `
    -LogPath $runLog

  $simulateArguments = @(
    $snapshot, '-runall',
    '-log', (Join-Path $logDirectory ($Testbench + '.xsim.log'))
  )
  $simulationOutput = @(Invoke-XsimTool -Executable 'xsim' `
    -ToolArguments $simulateArguments -LogPath $runLog)
  $verdicts = @($simulationOutput | Where-Object { $_ -eq 'ALL TESTS PASSED' })
  if ($verdicts.Count -ne 1) {
    throw 'The testbench must print exactly one ALL TESTS PASSED verdict.'
  }

  Add-Content -LiteralPath $runLog -Value 'ALL TESTS PASSED' -Encoding ASCII
  $verificationLog = @(Get-Content -LiteralPath $runLog)
  if (($verificationLog[-1] -ne 'ALL TESTS PASSED') -or
      ($verificationLog -match 'FAILED')) {
    throw 'The combined verification log does not satisfy the pass rule.'
  }
  Write-Host "Verification log: $runLog"
  Write-Host 'ALL TESTS PASSED'
  exit 0
} catch {
  $failureMessage = 'FAILED: ' + $_.Exception.Message
  if ($null -ne $runLog) {
    Add-Content -LiteralPath $runLog -Value $failureMessage -Encoding ASCII
  }
  Write-Host $failureMessage
  exit 1
}
