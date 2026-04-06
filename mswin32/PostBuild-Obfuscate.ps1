<#
.SYNOPSIS
    Post-build obfuscation pipeline for nmap Windows binary.
    Run after Build.bat to strip identifying artifacts from the compiled exe.

.PARAMETER SourceExe
    Path to the freshly compiled nmap.exe (default: .\Release\nmap.exe)

.PARAMETER OutputName
    Target filename for the obfuscated binary (default: netdiag.exe)

.PARAMETER OutputDir
    Directory to place the obfuscated binary (default: C:\Windows\Temp)

.EXAMPLE
    .\PostBuild-Obfuscate.ps1
    .\PostBuild-Obfuscate.ps1 -SourceExe ".\Release\nmap.exe" -OutputName "svchost_net.exe" -OutputDir "C:\ProgramData\Microsoft"
#>
param(
    [string]$SourceExe  = ".\Release\nmap.exe",
    [string]$OutputName = "netdiag.exe",
    [string]$OutputDir  = "$env:SystemRoot\Temp"
)

$ErrorActionPreference = "Stop"
$OutputPath = Join-Path $OutputDir $OutputName

# --- Step 1: Verify source exists ---
if (-not (Test-Path $SourceExe)) {
    Write-Error "[!] Source binary not found: $SourceExe"
    Write-Host "    Run Build.bat first, then run this script."
    exit 1
}
Write-Host "[*] Source: $SourceExe"

# --- Step 2: Copy to target location ---
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
Copy-Item -Path $SourceExe -Destination $OutputPath -Force
Write-Host "[+] Copied to: $OutputPath"

# --- Step 3: UPX packing ---
$upx = Get-Command upx -ErrorAction SilentlyContinue
if ($upx) {
    Write-Host "[*] UPX found at: $($upx.Source)"
    Write-Host "[*] Packing (--best --ultra-brute) ..."
    & upx --best --ultra-brute $OutputPath
    Write-Host "[+] UPX packing done"
} else {
    Write-Warning "[!] UPX not found in PATH — skipping compression."
    Write-Host "    Install UPX: winget install upx  OR  choco install upx"
}

# --- Step 4: String audit — make sure no nmap/Insecure artifacts remain ---
Write-Host ""
Write-Host "[*] Auditing strings for identifying artifacts..."

$stringsCmd = Get-Command strings -ErrorAction SilentlyContinue
if (-not $stringsCmd) {
    $stringsCmd = Get-Command strings64 -ErrorAction SilentlyContinue
}

if ($stringsCmd) {
    $hits = & $stringsCmd.Source $OutputPath 2>$null |
            Select-String -Pattern "nmap|Insecure\.Org|scanme|nmap\.org" -CaseSensitive:$false

    if ($hits) {
        Write-Warning "[!] Residual identifying strings found:"
        $hits | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "[+] Clean — no nmap/Insecure artifacts in ASCII strings."
    }
} else {
    Write-Warning "[!] strings.exe not found. Download Sysinternals Strings:"
    Write-Host "    https://learn.microsoft.com/en-us/sysinternals/downloads/strings"
    Write-Host "    Then re-run audit manually:"
    Write-Host "    strings64.exe $OutputPath | findstr /i nmap"
}

# --- Step 5: PE metadata check via sigcheck (optional) ---
$sigcheck = Get-Command sigcheck -ErrorAction SilentlyContinue
if ($sigcheck) {
    Write-Host ""
    Write-Host "[*] PE version info (sigcheck):"
    & sigcheck -nobanner $OutputPath
}

# --- Step 6: Print operational evasion flags ---
Write-Host ""
Write-Host "========================================="
Write-Host " Operational evasion flags (copy-paste):"
Write-Host "========================================="
Write-Host ""
Write-Host "  $OutputPath -sS -T1 -f --mtu 24 -D RND:5,ME -g 443 --scan-delay 3s --data-length 40 --spoof-mac 0 --randomize-hosts -Pn <target>"
Write-Host ""
Write-Host "[*] Flags breakdown:"
Write-Host "    -sS          SYN scan (raw packets, no full 3-way handshake)"
Write-Host "    -T1          Sneaky timing (~15s between probes, evades rate detectors)"
Write-Host "    -f --mtu 24  Fragment packets to break NIDS payload signatures"
Write-Host "    -D RND:5,ME  5 random decoys + real source — confuses attribution"
Write-Host "    -g 443       Source port 443 — traffic looks like HTTPS reply"
Write-Host "    --scan-delay Rate-limits bursts below anomaly thresholds"
Write-Host "    --data-length Pads packets with random bytes, breaks size-based sigs"
Write-Host "    --spoof-mac 0 Randomize L2 MAC on each run"
Write-Host "    -Pn          Skip host discovery pings (quieter initial phase)"
Write-Host ""
Write-Host "[+] Done. Binary at: $OutputPath"
