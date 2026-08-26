# Adapted from the PowerShell protocol adapter used by moonbitlang/moon-ide-tests:
# https://github.com/moonbitlang/moon-ide-tests/tree/main/scripts

$ErrorActionPreference = "Continue"
$lastStatus = 0
$sawDivider = $false
$cramStateFile = $null
$loadedCramState = $false
$skippingInternalFunction = $false
$global:TESTDIR = $env:TESTDIR

function Write-LfLine {
  param([string] $Text)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes("$Text`n")
  [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
}

function Convert-CramExport {
  param([string] $Line)

  if ($Line -notmatch '^export ([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
    return $false
  }

  $name = $Matches[1]
  $value = Convert-ShellValue $Matches[2]
  [Environment]::SetEnvironmentVariable($name, $value, "Process")

  # BASIC.md uses the Bash-compatible $TESTDIR spelling. Defining the same
  # PowerShell variable lets its commands remain shared by both platforms.
  if ($name -eq "TESTDIR") {
    Set-Variable -Name $name -Value $value -Scope Global
  }
  return $true
}

function Convert-ShellValue {
  param([string] $Value)

  if (
    ($Value.Length -ge 2) -and
    (($Value[0] -eq "'" -and $Value[$Value.Length - 1] -eq "'") -or
     ($Value[0] -eq '"' -and $Value[$Value.Length - 1] -eq '"'))
  ) {
    return $Value.Substring(1, $Value.Length - 2)
  }
  return $Value
}

function Import-CramPowerShellState {
  if ($script:loadedCramState -or !$script:cramStateFile) {
    return
  }
  $script:loadedCramState = $true
  if (!(Test-Path -LiteralPath $script:cramStateFile)) {
    return
  }

  foreach ($stateLine in Get-Content -LiteralPath $script:cramStateFile) {
    if ($stateLine.Trim() -ne "") {
      Invoke-Expression $stateLine
    }
  }
}

function Set-CramStatePath {
  param([string] $Line)

  if ($Line -notmatch '^__MOON_CRAM_TEMP_STATE_PATH=(.*)$') {
    return $false
  }

  $stateDirectory = Convert-ShellValue $Matches[1]
  if ($stateDirectory) {
    $script:cramStateFile = Join-Path $stateDirectory "powershell-state.ps1"
    Import-CramPowerShellState
  }
  return $true
}

function Test-CramInternalLine {
  param([string] $Line)

  $trimmed = $Line.Trim()
  if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
    return $true
  }
  if ($trimmed.StartsWith("function __moon_cram_")) {
    $script:skippingInternalFunction = $true
    return $true
  }
  if ($script:skippingInternalFunction) {
    if ($trimmed -eq "}") {
      $script:skippingInternalFunction = $false
    }
    return $true
  }
  if ($trimmed.StartsWith("shopt ")) {
    return $true
  }
  if ($trimmed.StartsWith("[ -f ") -or $trimmed.StartsWith("[ 1 -eq ")) {
    return $true
  }
  return $false
}

function Test-PersistableCramLine {
  param([string] $Line)

  $trimmed = $Line.TrimStart()
  return (
    $trimmed.StartsWith('$env:') -or
    $trimmed.StartsWith('$script:') -or
    $trimmed.StartsWith('function ')
  )
}

function Save-CramPowerShellState {
  param([string] $Line)

  if (!$script:cramStateFile -or !(Test-PersistableCramLine $Line)) {
    return
  }

  $stateDirectory = Split-Path -Parent $script:cramStateFile
  if (!(Test-Path -LiteralPath $stateDirectory)) {
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
  }

  $existing = @()
  if (Test-Path -LiteralPath $script:cramStateFile) {
    $existing = Get-Content -LiteralPath $script:cramStateFile
  }
  if (!($existing -contains $Line)) {
    Add-Content -LiteralPath $script:cramStateFile -Value $Line -Encoding utf8
  }
}

function Write-CramDivider {
  param([string] $Line)

  if (!$Line.StartsWith("echo ")) {
    return $false
  }

  $divider = Convert-ShellValue $Line.Substring(5)
  if (
    $divider.StartsWith("~~~~~~~~EXECDIVIDER::") -and
    $divider.EndsWith("::`$?")
  ) {
    $prefix = $divider.Substring(0, $divider.Length - 4)
    $script:sawDivider = $true
    Write-LfLine "$prefix::$script:lastStatus"
    return $true
  }
  return $false
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
  if (Set-CramStatePath $line) {
    $lastStatus = 0
    continue
  }
  if (Test-CramInternalLine $line) {
    continue
  }
  if (Convert-CramExport $line) {
    $lastStatus = 0
    continue
  }
  if (Write-CramDivider $line) {
    continue
  }

  $global:LASTEXITCODE = $null
  try {
    Invoke-Expression $line
    Save-CramPowerShellState $line
    if ($null -ne $global:LASTEXITCODE) {
      $lastStatus = [int] $global:LASTEXITCODE
    } elseif ($?) {
      $lastStatus = 0
    } else {
      $lastStatus = 1
    }
  } catch {
    Write-Error $_
    $lastStatus = 1
  }
}

if ($sawDivider) {
  exit 0
}
exit $lastStatus
