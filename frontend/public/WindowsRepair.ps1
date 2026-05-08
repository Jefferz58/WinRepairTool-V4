#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinRepair-Toolkit v4.6 - Dashboard TUI with Live Progress Percentages
.DESCRIPTION
    Fixed single-screen dashboard interface.
    Phase 1: Pre-flight checks
    Phase 2: Instant diagnostic scan (No auto-running background tools)
    Phase 3: Interactive Action Loop (Never exits without user command)
    New: Real-time percentage tracking for DISM and SFC operations.
.NOTES
    v4.6 | Admin | Win10/11 | PS 5.1+ | 
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ============================================================================
# CONFIG
# ============================================================================
$ToolkitVersion = "4.7"
$LogDir         = "C:\RepairLogs"
$Timestamp      = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile        = Join-Path $LogDir "WinRepair_$Timestamp.txt"
$StateFile      = Join-Path $LogDir "resume-state.json"
$ResumeTaskName = "WinRepair-AutoResume"
$ScriptPath     = $PSCommandPath
if (-not $ScriptPath) { $ScriptPath = $MyInvocation.MyCommand.Path }

try { if (-not (Test-Path $LogDir)) { New-Item $LogDir -ItemType Directory -Force | Out-Null } } catch {}

# ============================================================================
# CONSOLE SETUP
# ============================================================================
try {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    $Host.UI.RawUI.WindowTitle     = "WinRepair-Toolkit v$ToolkitVersion"
    $Host.UI.RawUI.BufferSize      = New-Object System.Management.Automation.Host.Size(120, 50)
    $Host.UI.RawUI.WindowSize      = New-Object System.Management.Automation.Host.Size(120, 50)
} catch {}
Clear-Host

# ============================================================================
# LOG 
# ============================================================================
function Log([string]$Msg) {
    try { Add-Content $LogFile "[$([DateTime]::Now.ToString('HH:mm:ss'))] $Msg" -EA SilentlyContinue } catch {}
}

# ============================================================================
# TUI DRAWING ENGINE
# ============================================================================
function Write-At {
    param([int]$Row, [int]$Col, [string]$Text, [string]$FG = "Gray", [string]$BG = "Black")
    try {
        $Host.UI.RawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates($Col, $Row)
        Write-Host $Text -ForegroundColor $FG -BackgroundColor $BG -NoNewline
    } catch {}
}

function Clear-Row {
    param([int]$Row, [int]$StartCol = 0)
    Write-At $Row $StartCol (" " * (119 - $StartCol)) "Gray"
}

function Clear-Region {
    param([int]$StartRow, [int]$EndRow, [int]$StartCol = 0)
    for ($r = $StartRow; $r -le $EndRow; $r++) { Clear-Row $r $StartCol }
}

function Draw-HLine { param([int]$Row, [string]$Char = "-", [string]$Color = "DarkCyan") Write-At $Row 0 ($Char * 120) $Color }

# ============================================================================
# SYSTEM INFO 
# ============================================================================
$SerialNumber = "UNKNOWN"; $Manufacturer = "UNKNOWN"; $ModelName = "UNKNOWN"
$BiosVersion = "UNKNOWN"; $BiosDate = "UNKNOWN"; $OSBuild = "UNKNOWN"; $OSInstall = "UNKNOWN"
try {
    $bios = Get-WmiObject Win32_BIOS -EA SilentlyContinue
    if ($bios) { $SerialNumber = $bios.SerialNumber.Trim(); $BiosVersion = $bios.SMBIOSBIOSVersion; $BiosDate = $bios.ReleaseDate.Substring(0,8) }
    $cs = Get-WmiObject Win32_ComputerSystem -EA SilentlyContinue
    if ($cs) { $Manufacturer = $cs.Manufacturer.Trim(); $ModelName = $cs.Model.Trim() }
    $os = Get-WmiObject Win32_OperatingSystem -EA SilentlyContinue
    if ($os) { $OSBuild = $os.BuildNumber; $OSInstall = $os.InstallDate.Substring(0,8) }
} catch {}

# ============================================================================
# TOOL CATALOG
# ============================================================================
$ToolCatalog = [ordered]@{
    "01" = @{ Name="Disk Cleanup";           Cmd="cleanmgr.exe"; Args="/sagerun:100";                                 Cat="Repair"; Reboot=$false; Est="2-5m" }
    "02" = @{ Name="DISM CheckHealth";       Cmd="DISM.exe";     Args="/Online /Cleanup-Image /CheckHealth";          Cat="Diag";   Reboot=$false; Est="1m" }
    "03" = @{ Name="DISM ScanHealth";        Cmd="DISM.exe";     Args="/Online /Cleanup-Image /ScanHealth";           Cat="Diag";   Reboot=$false; Est="5-15m" }
    "04" = @{ Name="DISM RestoreHealth";     Cmd="DISM.exe";     Args="/Online /Cleanup-Image /RestoreHealth";        Cat="Repair"; Reboot=$false; Est="10-30m" }
    "05" = @{ Name="SFC /verifyonly";        Cmd="sfc.exe";      Args="/verifyonly";                                   Cat="Diag";   Reboot=$false; Est="5-10m" }
    "06" = @{ Name="SFC /scannow";           Cmd="sfc.exe";      Args="/scannow";                                      Cat="Repair"; Reboot=$true;  Est="10-20m" }
    "07" = @{ Name="DISM ComponentCleanup";  Cmd="DISM.exe";     Args="/Online /Cleanup-Image /StartComponentCleanup";Cat="Repair"; Reboot=$false; Est="3-10m" }
    "08" = @{ Name="CHKDSK /f /r /x";        Cmd="chkdsk";       Args="C: /f /r /x";                                   Cat="Repair"; Reboot=$true;  Est="varies" }
    "09" = @{ Name="TCP/IP Reset";           Cmd="netsh";        Args="int ip reset";                                  Cat="Repair"; Reboot=$true;  Est="1m" }
    "10" = @{ Name="Winsock Reset";          Cmd="netsh";        Args="winsock reset";                                 Cat="Repair"; Reboot=$true;  Est="1m" }
    "11" = @{ Name="Flush DNS";              Cmd="ipconfig";     Args="/flushdns";                                     Cat="Repair"; Reboot=$false; Est="<1m" }
    "12" = @{ Name="Perfmon Report";         Cmd="perfmon.exe";  Args="/report";                                       Cat="Diag";   Reboot=$false; Est="2m" }
}

$ToolStatus = [ordered]@{}
foreach ($id in $ToolCatalog.Keys) { $ToolStatus[$id] = @{ Status="--"; Time=""; Message="" } }

$Findings = @{
    DriversOutdated = 0; DriverList = @(); LowDiskSpace = $false; DiskFreePercent = 0; NetworkIssue = $false; Issues = @()
}

# ============================================================================
# STATE PERSISTENCE & INTERNET CHECK
# ============================================================================
function Save-State {
    param([string[]]$Remaining, [bool]$AutoReboot, [string]$Mode)
    try {
        @{ Version=$ToolkitVersion; SavedAt=(Get-Date -Format 'o')
           Remaining=$Remaining; AutoReboot=$AutoReboot; Mode=$Mode
           OriginalLog=$LogFile } | ConvertTo-Json | Set-Content $StateFile -Force
    } catch {}
}
function Load-State { if (-not (Test-Path $StateFile)) { return $null }; try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch { return $null } }
function Clear-State { if (Test-Path $StateFile) { Remove-Item $StateFile -Force -EA SilentlyContinue } }

function Register-ResumeTask {
    Unregister-ResumeTask
    try {
        $a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Resume"
        $t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4)
        Register-ScheduledTask -TaskName $ResumeTaskName -Action $a -Trigger $t -Principal $p -Settings $s -Description "WinRepair auto-resume" -Force | Out-Null
    } catch {}
}
function Unregister-ResumeTask { try { if (Get-ScheduledTask -TaskName $ResumeTaskName -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false -EA SilentlyContinue } } catch {} }

function Test-InternetConnection {
    try {
        $req = [System.Net.WebRequest]::Create("http://www.msftconnecttest.com/connecttest.txt")
        $req.Timeout = 3000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch { return $false }
}

# ============================================================================
# SCREEN LAYOUT & UPDATE LOGIC 
# ============================================================================

$ROW_TITLE     = 0
$ROW_SYS1      = 1
$ROW_SYS2      = 2
$ROW_DIV1      = 3
$ROW_STATUS    = 4
$ROW_DIV2      = 5
$ROW_TOOLS     = 6
$ROW_DIV3      = 18
$ROW_PREFLIGHT = 19
$ROW_DIV4      = 24
$ROW_DRIVERS   = 25
$ROW_DIV5      = 31
$ROW_FINDINGS  = 32
$ROW_DIV6      = 36
$ROW_MENU      = 37
$ROW_DIV7      = 45
$ROW_FOOTER    = 46

function Draw-Layout {
    Clear-Host
    Write-At $ROW_TITLE 0 (" WinRepair-Toolkit v$ToolkitVersion " + " " * 40 + "Serial: $SerialNumber " + " " * 10 + (Get-Date -Format 'yyyy-MM-dd HH:mm')) "White" "DarkBlue"
    Write-At $ROW_SYS1 0 "  $Manufacturer $ModelName" "Cyan"
    Write-At $ROW_SYS1 50 "BIOS: $BiosVersion ($BiosDate)" "DarkGray"
    Write-At $ROW_SYS1 95 "User: $env:USERNAME" "DarkGray"
    Write-At $ROW_SYS2 0 "  $env:COMPUTERNAME" "Cyan"
    Write-At $ROW_SYS2 50 "OS Build: $OSBuild (Installed: $OSInstall)" "DarkGray"
    Draw-HLine $ROW_DIV1
    Write-At $ROW_STATUS 0 "  STATUS: " "White"
    Write-At $ROW_STATUS 10 "Ready" "DarkGray"
    Draw-HLine $ROW_DIV2
    Write-At $ROW_TOOLS 0 "  ID  TOOL                     STATUS    TIME     ID  TOOL                     STATUS    TIME" "DarkCyan"
    
    $keys = @($ToolCatalog.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $row = $ROW_TOOLS + 1 + ($i % 6)
        $col = if ($i -lt 6) { 0 } else { 55 }
        $id = $keys[$i]
        $t = $ToolCatalog[$id]
        $rebootMark = if ($t.Reboot) { "*" } else { " " }
        Write-At $row $($col + 2) ("{0} {1}{2}" -f $id, $rebootMark, $t.Name.PadRight(22)) "Gray"
        
        $ts = $ToolStatus[$id]
        $txt = switch($ts.Status){"OK"{"[  OK  ]"}"FAIL"{"[ FAIL ]"}"RUN"{"[ RUN  ]"}"SKIP"{"[ SKIP ]"}"QUEUE"{"[QUEUED]"}"REBOOT"{"[RBOOT ]"}default{"[  --  ]"}}
        $clr = switch($ts.Status){"OK"{"Green"}"FAIL"{"Red"}"RUN"{"Yellow"}"SKIP"{"DarkGray"}"QUEUE"{"Cyan"}"REBOOT"{"Magenta"}default{"DarkGray"}}
        Write-At $row $($col + 28) $txt $clr
        if ($ts.Time) { Write-At $row $($col + 38) $ts.Time.PadRight(7) "DarkGray" }
    }
    
    Draw-HLine $ROW_DIV3
    Write-At $ROW_PREFLIGHT 0 "  PRE-FLIGHT CHECKS" "DarkCyan"
    Draw-HLine $ROW_DIV4
    Write-At $ROW_DRIVERS 0 "  LENOVO DRIVER STATUS" "DarkCyan"
    Draw-HLine $ROW_DIV5
    Write-At $ROW_FINDINGS 0 "  DIAGNOSTIC FINDINGS" "DarkCyan"
    Draw-HLine $ROW_DIV6
    Write-At $ROW_MENU 0 "  ACTION MENU" "DarkCyan"
    Draw-HLine $ROW_DIV7
    Write-At $ROW_FOOTER 0 "  * = requires reboot   |   Log: $LogFile" "DarkGray"
}

function Update-Status {
    param([string]$Text, [string]$Color = "White", [string]$PctValue = "")
    Clear-Row $ROW_STATUS
    Write-At $ROW_STATUS 0 "  STATUS: " "White"
    $maxLen = if ($PctValue) { 56 } else { 108 }
    $display = if ($Text.Length -gt $maxLen) { $Text.Substring(0, $maxLen - 3) + "..." } else { $Text }
    Write-At $ROW_STATUS 10 $display $Color
    if ($PctValue) {
        $pctNum = 0.0
        if ($PctValue -match "([0-9]{1,3}(\.[0-9]+)?)") {
            $pctNum = [double]$matches[1]
            if ($pctNum -gt 100) { $pctNum = 100 }
        }
        $barWidth = 28
        $filled   = [math]::Floor(($pctNum / 100) * $barWidth)
        $empty    = $barWidth - $filled
        $barStr   = "[" + ([string][char]9608 * $filled) + ([string][char]9617 * $empty) + "]"
        $pctStr   = ("{0,5:N1}%" -f $pctNum)
        $barColor = if ($pctNum -ge 90) { "Green" } elseif ($pctNum -ge 50) { "Cyan" } else { "Yellow" }
        Write-At $ROW_STATUS 68 $barStr $barColor
        Write-At $ROW_STATUS 101 $pctStr "Cyan"
    }
    Log "STATUS: $Text $PctValue"
}

function Update-ToolStatus {
    param([string]$ToolId, [string]$Status, [string]$Time = "", [string]$Color = "Gray")
    $keys = @($ToolCatalog.Keys); $idx = [array]::IndexOf($keys, $ToolId); if ($idx -lt 0) { return }
    $row = $ROW_TOOLS + 1 + ($idx % 6); $col = if ($idx -lt 6) { 0 } else { 55 }
    $txt = switch($Status){"OK"{"[  OK  ]"}"FAIL"{"[ FAIL ]"}"RUN"{"[ RUN  ]"}"SKIP"{"[ SKIP ]"}"QUEUE"{"[QUEUED]"}"REBOOT"{"[RBOOT ]"}default{"[  --  ]"}}
    $clr = switch($Status){"OK"{"Green"}"FAIL"{"Red"}"RUN"{"Yellow"}"SKIP"{"DarkGray"}"QUEUE"{"Cyan"}"REBOOT"{"Magenta"}default{"DarkGray"}}
    Write-At $row ($col + 28) $txt $clr
    if ($Time) { Write-At $row ($col + 38) $Time.PadRight(7) "DarkGray" } else { Write-At $row ($col + 38) "       " "DarkGray" }
    $ToolStatus[$ToolId].Status = $Status
    $ToolStatus[$ToolId].Time = $Time
    Log "Tool $ToolId ($($ToolCatalog[$ToolId].Name)): $Status $Time"
}

function Update-PreFlight {
    param([int]$Index, [string]$Label, [string]$Result, [string]$Color)
    $row = $ROW_PREFLIGHT + 1 + $Index
    Clear-Row $row
    Write-At $row 4 $Label.PadRight(35) "Gray"
    Write-At $row 40 $Result $Color
    Log "PreFlight: $Label = $Result"
}

function Update-Driver {
    param([int]$Index, [string]$Name, [string]$Local, [string]$Remote, [string]$Status, [string]$Color)
    $row = $ROW_DRIVERS + 1 + $Index
    if ($Index -ge 5) { return }
    Clear-Row $row
    $displayName = if ($Name.Length -gt 28) { $Name.Substring(0, 25) + "..." } else { $Name.PadRight(28) }
    Write-At $row 4 $displayName "Gray"
    Write-At $row 33 $Local.PadRight(16) "DarkGray"
    Write-At $row 50 $Remote.PadRight(16) "DarkGray"
    Write-At $row 67 $Status $Color
}

function Update-Finding {
    param([int]$Index, [string]$Text, [string]$Color = "Yellow")
    $row = $ROW_FINDINGS + 1 + $Index
    if ($Index -ge 3) { return }
    Clear-Row $row
    Write-At $row 4 $Text $Color
}

function Show-Menu {
    param([string[]]$Options)
    Clear-Region ($ROW_MENU + 1) ($ROW_MENU + 7)
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-At ($ROW_MENU + 1 + $i) 4 $Options[$i] "White"
    }
}

function Get-MenuChoice {
    param([string]$Prompt, [string[]]$ValidChoices)
    $pRow = $ROW_MENU + 7
    Clear-Row $pRow
    Write-At $pRow 4 $Prompt "Cyan"
    $Host.UI.RawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates(($Prompt.Length + 6), $pRow)
    while ($true) {
        $key = (Read-Host).Trim().ToUpper()
        if ($key -in $ValidChoices) { return $key }
        Clear-Row $pRow
        Write-At $pRow 4 "Invalid. $Prompt" "Red"
        $Host.UI.RawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates(($Prompt.Length + 16), $pRow)
    }
}

# ============================================================================
# PROCESS RUNNER WITH REAL-TIME PERCENTAGE TRACKING
# ============================================================================
function Invoke-ToolSilent {
    param([string]$ToolId)
    $tool = $ToolCatalog[$ToolId]; if (-not $tool) { return $false }
    Update-ToolStatus $ToolId "RUN"
    Update-Status "Running: $($tool.Name)..." "Yellow"
    $start = Get-Date

    # CHKDSK schedules itself via cmd pipe
    if ($tool.Cmd -eq "chkdsk") {
        try {
            "Y`n" | & cmd /c "chkdsk $($tool.Args)" 2>&1 | ForEach-Object { Log "  $_" }
            $el = ((Get-Date) - $start).ToString("mm\:ss")
            Update-ToolStatus $ToolId "OK" $el; return $true
        } catch {
            $el = ((Get-Date) - $start).ToString("mm\:ss")
            Update-ToolStatus $ToolId "FAIL" $el; return $false
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
        FileName=$tool.Cmd; Arguments=$tool.Args; UseShellExecute=$false
        RedirectStandardOutput=$true; RedirectStandardError=$true; CreateNoWindow=$true
    }
    $proc = New-Object System.Diagnostics.Process -Property @{ StartInfo=$psi }
    try { $proc.Start() | Out-Null }
    catch {
        $el = ((Get-Date) - $start).ToString("mm\:ss")
        Update-ToolStatus $ToolId "FAIL" $el; return $false
    }

    $lastPatience = $start
    $lastPct      = ""
    $outBuffer    = ""

    while (-not $proc.HasExited) {

        # Read char-by-char so carriage-return progress lines flush immediately
        # DISM and SFC use  (not 
) for their progress percentage updates
        while ($proc.StandardOutput.Peek() -gt -1) {
            $ch = [char]$proc.StandardOutput.Read()

            if ($ch -eq "`r" -or $ch -eq "`n") {
                $trim = $outBuffer.Trim()
                if ($trim) {
                    Log "  $trim"
                    # Match DISM/SFC percentage patterns: "14.3%" or "[ 62.3%]" or "Verification 14%"
                    if ($trim -match "[0-9]{1,3}(\.[0-9]+)?%") {
                        $m = [regex]::Match($trim, "[0-9]{1,3}(\.[0-9]+)?%")
                        $lastPct = $m.Value
                        Update-Status "Running: $($tool.Name)..." "Yellow" $lastPct
                    }
                }
                $outBuffer = ""
            } else {
                $outBuffer += $ch
            }
        }

        # Also check mid-buffer for inline progress (DISM writes  without 
)
        # Flush the buffer and check it even without a newline if it contains a %
        if ($outBuffer.Trim() -match "[0-9]{1,3}(\.[0-9]+)?%") {
            $m = [regex]::Match($outBuffer.Trim(), "[0-9]{1,3}(\.[0-9]+)?%")
            if ($m.Value -ne $lastPct) {
                $lastPct = $m.Value
                Update-Status "Running: $($tool.Name)..." "Yellow" $lastPct
                Log "  (progress) $($outBuffer.Trim())"
                $outBuffer = ""
            }
        }

        # Drain stderr
        while ($proc.StandardError.Peek() -gt -1) { $null = $proc.StandardError.Read() }

        # Update elapsed time in grid cell
        $now = Get-Date
        $el  = $now - $start
        $elS = "{0:D2}:{1:D2}" -f [int]$el.TotalMinutes, $el.Seconds
        Update-ToolStatus $ToolId "RUN" $elS

        # Patience message every 2 minutes
        if (($now - $lastPatience).TotalSeconds -ge 120) {
            $msg = "Still running: $($tool.Name) ($elS)"
            if ($tool.Name -like "*RestoreHealth*") { $msg = "DISM RestoreHealth ($elS) - 62.3%% pause is NORMAL" }
            Update-Status $msg "Cyan" $lastPct
            $lastPatience = $now
        }
        Start-Sleep -Milliseconds 100
    }

    # Flush any remaining buffer content
    $trim = $outBuffer.Trim()
    if ($trim) { Log "  $trim" }

    $exit = $proc.ExitCode
    $proc.Dispose()
    $el = ((Get-Date) - $start).ToString("mm\:ss")
    if ($exit -eq 0) { Update-ToolStatus $ToolId "OK" $el; return $true }
    else             { Update-ToolStatus $ToolId "FAIL" $el; return $false }
}

# ============================================================================
# RESUME & FLOW
# ============================================================================
$IsResume = $false; foreach ($a in $args) { if ($a -eq "-Resume") { $IsResume = $true } }

if ($IsResume) {
    $st = Load-State; Unregister-ResumeTask; if (-not $st -or -not $st.Remaining -or $st.Remaining.Count -eq 0) { Clear-State; exit 0 }
    Draw-Layout; Update-Status "RESUMING after reboot ($($st.Remaining.Count) tool(s) remaining)" "Magenta"
    $queue = [System.Collections.ArrayList]@($st.Remaining); $autoReboot = [bool]$st.AutoReboot
    while ($queue.Count -gt 0) {
        $id = $queue[0]; $queue.RemoveAt(0); Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $st.Mode
        $tool = $ToolCatalog[$id]; $ok = Invoke-ToolSilent $id
        if ($tool.Reboot -and $queue.Count -gt 0) {
            if ($autoReboot) { Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $st.Mode; Register-ResumeTask; Update-Status "Auto-rebooting in 15s..." "Magenta"; Start-Sleep 15; Restart-Computer -Force; exit 0 }
            else { Update-Status "$($tool.Name) needs reboot. Press Y to reboot, N to skip." "Yellow"; $r = Get-MenuChoice "Reboot now? [Y/N]:" @("Y","N"); if ($r -eq "Y") { Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $st.Mode; Register-ResumeTask; Update-Status "Rebooting in 10s..." "Magenta"; Start-Sleep 10; Restart-Computer -Force; exit 0 } else { Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $st.Mode; exit 0 } }
        }
    }
    Clear-State; Update-Status "ALL QUEUED TOOLS COMPLETE" "Green"
    Show-Menu @(
        "Resume Task Complete. What would you like to do next?",
        "[R] Relaunch Dashboard (Re-scan system)",
        "[E] Exit Script"
    )
    $c = Get-MenuChoice "Enter [R/E]:" @("R","E")
    if ($c -eq "R") { & $ScriptPath; exit 0 }
    exit 0
}

Set-Content $LogFile "WinRepair-Toolkit v$ToolkitVersion Fresh Start" -Force
Draw-Layout
$stale = Load-State; if ($stale) { Update-Status "Previous session found. Resume? Y/N" "Yellow"; Show-Menu @("[Y] Resume workflow", "[N] Start fresh"); if ((Get-MenuChoice "Resume? [Y/N]:" @("Y","N")) -eq "Y") { & $ScriptPath -Resume; exit 0 } else { Clear-State; Unregister-ResumeTask } }

Update-Status "Setup: Auto-reboot preference" "Cyan"; Show-Menu @("[Y] Auto-reboot ON", "[N] Auto-reboot OFF (manual)"); $autoReboot = (Get-MenuChoice "Auto-reboot? [Y/N]:" @("Y","N")) -eq "Y"
Clear-Region ($ROW_MENU + 1) ($ROW_MENU + 7); Update-Status "Auto-reboot: $(if($autoReboot){'ON'}else{'OFF'})" "Green"; Start-Sleep 1

# PHASE 1
Update-Status "Phase 1: Pre-flight checks..." "Cyan"; $gp = $false; $chkIdx = 0
$ep = Get-ExecutionPolicy; if ($ep -in @("Restricted","AllSigned")) { Update-PreFlight $chkIdx "ExecutionPolicy" "$ep - BLOCKED" "Red"; $gp=$true } else { Update-PreFlight $chkIdx "ExecutionPolicy" "$ep [OK]" "Green" }; $chkIdx++
try { $d = Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\System" -Name "DisableCMD" -EA SilentlyContinue; if ($d -and $d.DisableCMD -ne 0) { Update-PreFlight $chkIdx "DisableCMD" "Enabled - BLOCKED" "Red"; $gp=$true } else { Update-PreFlight $chkIdx "DisableCMD" "Not set [OK]" "Green" } } catch { Update-PreFlight $chkIdx "DisableCMD" "Not set [OK]" "Green" }; $chkIdx++
if (-not (Test-Path "$env:SystemRoot\System32\Dism.exe") -or -not (Test-Path "$env:SystemRoot\System32\sfc.exe")) { Update-PreFlight $chkIdx "Core tools" "MISSING" "Red"; $gp=$true } else { Update-PreFlight $chkIdx "Core tools (DISM, SFC)" "Found [OK]" "Green" }; $chkIdx++
$hasInternet = Test-InternetConnection; if ($hasInternet) { Update-PreFlight $chkIdx "Internet" "Connected [OK]" "Green" } else { Update-PreFlight $chkIdx "Internet" "No connection" "Yellow" }
if ($gp) { Update-Status "PRE-FLIGHT FAILED" "Red"; Show-Menu @("[N] Exit"); Get-MenuChoice "Press N:" @("N"); exit 1 }

# PHASE 2
Update-Status "Phase 2: Fast Diagnostic scan..." "Cyan"
if ($Manufacturer -like "*Lenovo*" -and $hasInternet) {
    try {
        $body = @{ sn=$SerialNumber; langCode="en"; machineType="" } | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "https://pcsupport.lenovo.com/us/en/api/v4/upsell/redport/getIBasedDrivers" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 30 -EA Stop
        $local = Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Select-Object DeviceName, DriverVersion
        $drvIdx = 0; foreach ($d in $resp.data) { if ($drvIdx -ge 5) { break }; $m = $local | Where-Object { $_.DeviceName -like "*$($d.Title.Split(' ')[0])*" } | Select-Object -First 1; if ($m) { if ($m.DriverVersion -ne $d.Version) { Update-Driver $drvIdx $d.Title $m.DriverVersion $d.Version "[UPDATE]" "Yellow"; $Findings.DriversOutdated++; $Findings.DriverList += $d.Title } else { Update-Driver $drvIdx $d.Title $m.DriverVersion $d.Version "[Current]" "Green" }; $drvIdx++ } }
        if ($Findings.DriversOutdated -gt 0) { $Findings.Issues += "$($Findings.DriversOutdated) driver updates" }
        if ($drvIdx -eq 0) { Update-Driver 0 "No updates found for this model" "--" "--" "[Up to date]" "Green" }
    } catch { Update-Driver 0 "API query failed" "--" "--" "[Skipped]" "DarkGray" }
}

try { $cd = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"; $pct = [math]::Round(($cd.FreeSpace/$cd.Size)*100, 1); if ($pct -lt 20) { $Findings.LowDiskSpace = $true; $Findings.Issues += "Low disk ($pct%)" } } catch {}
if (-not $hasInternet) { $Findings.Issues += "No internet" }

$fIdx = 0; if ($Findings.Issues.Count -eq 0) { Update-Finding 0 "GREEN ACROSS THE BOARD" "Green" } else { foreach ($i in $Findings.Issues) { if ($fIdx -ge 3) { break }; Update-Finding $fIdx "> $i" "Yellow"; $fIdx++ } }
Update-Status "Phase 2 complete" "Green"; Start-Sleep 1

# ============================================================================
# PHASE 3 - INTERACTIVE LOOP
# ============================================================================
while ($true) {
    Clear-Region ($ROW_MENU + 1) ($ROW_MENU + 7)
    Update-Status "Phase 3: Choose action" "Cyan"
    Show-Menu @(
        "[F] Full repair   - All 12 tools in recommended order",
        "[Q] Quick repair  - Only fix detected issues",
        "[D] Drivers only  - Launch Lenovo Vantage",
        "[A] Advanced mode - Pick individual tools (override order)",
        "[R] Report only   - Export findings to file",
        "[N] Exit script   - Close dashboard cleanly"
    )
    $choice = Get-MenuChoice "Enter [F/Q/D/A/R/N]:" @("F","Q","D","A","R","N")
    Clear-Region ($ROW_MENU + 1) ($ROW_MENU + 7)
    
    $queue = [System.Collections.ArrayList]@()
    $actionComplete = $false

    switch ($choice) {
        "F" { foreach ($id in $ToolCatalog.Keys) { [void]$queue.Add($id) } }
        "Q" { 
            if ($Findings.LowDiskSpace) { [void]$queue.Add("01") }
            
            # Since auto-scan is disabled, Quick Repair will default to running standard DISM/SFC
            [void]$queue.Add("04")
            [void]$queue.Add("06")
            
            if ($Findings.NetworkIssue) { [void]$queue.Add("09"); [void]$queue.Add("10"); [void]$queue.Add("11") }
        }
        "D" { 
            $vp = @("C:\Program Files (x86)\Lenovo\VantageService\Vantage.exe","C:\Program Files\Lenovo\VantageService\Vantage.exe","C:\Program Files\Lenovo\System Update\TVSU.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($vp) { Start-Process $vp; Update-Status "Lenovo Vantage launched." "Green" }
            else { Update-Status "Vantage not found. Visit pcsupport.lenovo.com" "Yellow" }
            $actionComplete = $true
        }
        "A" { 
            Show-Menu @("Pick tool IDs (comma-separated). e.g., 04,06,11"); Write-At ($ROW_MENU+6) 4 "Enter IDs: " "Cyan"
            $Host.UI.RawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates(15, ($ROW_MENU+6))
            $rawStr = (Read-Host).Trim()
            if ($rawStr) {
                $rawIds = ($rawStr -split ",") | ForEach-Object { $_.Trim().PadLeft(2,"0") } | Where-Object { $_ -and $ToolCatalog.Contains($_) } | Sort-Object { [int]$_ }
                if ($rawIds.Count -gt 0) { foreach ($id in $rawIds) { [void]$queue.Add($id) } }
                else { Update-Status "No valid IDs entered." "Red"; $actionComplete = $true }
            } else {
                $actionComplete = $true
            }
        }
        "R" { 
            $p = Join-Path $LogDir "DiagReport_$Timestamp.txt"; "WinRepair Report`nSerial: $SerialNumber`nIssues: $($Findings.Issues -join ', ')" | Set-Content $p; 
            Update-Status "Report saved to $p" "Green"
            $actionComplete = $true
        }
        "N" { exit 0 }
    }

    if ($queue.Count -gt 0) {
        foreach ($id in $queue) { Update-ToolStatus $id "QUEUE" }
        Update-Status "Executing $($queue.Count) tool(s)..." "Cyan"
        
        while ($queue.Count -gt 0) {
            $id = $queue[0]; $queue.RemoveAt(0); Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $choice
            if ($id -in @("02","05") -and $ToolStatus[$id].Status -eq "OK") { continue }
            $ok = Invoke-ToolSilent $id
            
            if ($ToolCatalog[$id].Reboot -and $queue.Count -gt 0) {
                Update-ToolStatus $id "REBOOT"
                if ($autoReboot) { 
                    Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $choice
                    Register-ResumeTask
                    Update-Status "Auto-rebooting in 15s..." "Magenta"
                    Start-Sleep 15; Restart-Computer -Force; exit 0 
                } else { 
                    Update-Status "$($ToolCatalog[$id].Name) needs reboot." "Yellow"
                    Show-Menu @("[Y] Reboot now (resumes automatically)", "[N] Skip reboot (pauses queue)")
                    if ((Get-MenuChoice "Reboot now? [Y/N]:" @("Y","N")) -eq "Y") { 
                        Save-State -Remaining $queue -AutoReboot $autoReboot -Mode $choice
                        Register-ResumeTask
                        Update-Status "Rebooting in 10s..." "Magenta"
                        Start-Sleep 10; Restart-Computer -Force; exit 0 
                    } else { 
                        Update-Status "Queue paused. Re-run script later to resume." "Yellow"
                        exit 0 
                    } 
                }
            }
        }
        Clear-State
        Update-Status "ALL QUEUED TOOLS COMPLETE" "Green"
        $actionComplete = $true
    }

    if ($actionComplete) {
        Show-Menu @(
            "Task Complete. What would you like to do next?",
            "[M] Main Menu        (Continue troubleshooting)",
            "[R] Reboot System    (Apply changes/drivers)",
            "[E] Record & Exit    (Save final report and close)"
        )
        $post = Get-MenuChoice "Enter [M/R/E]:" @("M","R","E")
        Clear-Region ($ROW_MENU + 1) ($ROW_MENU + 7)
        
        if ($post -eq "M") {
            continue 
        } elseif ($post -eq "R") {
            Update-Status "Rebooting in 10s..." "Magenta"
            Start-Sleep 10
            Restart-Computer -Force
            exit 0
        } elseif ($post -eq "E") {
            $p = Join-Path $LogDir "FinalReport_$Timestamp.txt"
            "WinRepair Final Report`nSerial: $SerialNumber`nIssues Detected: $($Findings.Issues -join ', ')`n`nCompleted Tools:" | Set-Content $p -Force
            foreach ($key in $ToolStatus.Keys) {
                if ($ToolStatus[$key].Status -in @("OK","FAIL")) {
                    "$($ToolCatalog[$key].Name) - $($ToolStatus[$key].Status)" | Add-Content $p
                }
            }
            Update-Status "Final report saved to $p. Exiting in 3s..." "Green"
            Start-Sleep 3
            exit 0
        }
    }
}