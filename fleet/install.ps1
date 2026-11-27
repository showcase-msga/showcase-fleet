# Showcase Fleet installer (published 28 Nov 2026, catalogue 7). Installs Fleet on this NUC from a one-time code made on its page in
# Showcase Fleet (document.showcase.space/fleet). In PowerShell opened as administrator:
#   $code='K7Q2-9WXM'; irm '<this file>' | iex
# or run install_showcase_fleet.bat from the install link, as administrator.
# It: checks the release catalogue's signature against Jordan's public key (written into this file), enrols this
# NUC (the code becomes its own device token), installs Fleet and the NUC's ticked modules, checks them, and
# reports what's on the NUC. Every package is checked against the signed catalogue before it's unpacked.
# Nothing secret is in this file. If anything fails before enrolling, nothing on the NUC has changed.
# Trial 14 (26 Nov 2026): once enrolled, it tells the dashboard each step as it starts, and where it stopped and why
# if it does (shown as the NUC's problems on its page), with the NUC's serial number and MACs. MAB Circa 100 stopped
# after enrolling on 23 Nov and nobody could tell where. A window closed partway still leaves its last step there.
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $CatalogueUrl = 'https://raw.githubusercontent.com/showcase-msga/showcase-fleet/main/fleet/catalogue.json'
  $PublicKeyXml = '<RSAKeyValue><Modulus>rlAnfZ9KHh2MNj7c6lHBvX6aQwzrvHu/j162HvOZamAemqhXYwoLf1elEnGQs5I1FoQqkRpBD3B5OxoGZ0llfQQSfif08nIRZJwI3DCjfJeZxKZqTefguO98ecwybzHvd/NNEETznJA2Q47ylZ9pcdLH9jPckWJ1YP9sZ2nPbFJ9VH0791KTZwhAB+0yAy/QCiT8GpEFjT6MpcGZmO1+bCHKqN3lWSx8yRFyvOK/+6w3uI3IJpz1M3XUVnK5faFAZBse1nPPL1nZl1oO+xJbQvBlTXxH+IYBjqfLrE4rlhhqMGlHay4nyNYSWpdU9dfatSZRIyC4zMkJs9oVoFefwkJzliuTzkQBzb+zQsWU/UMQTC/oQ2mOg8OUVmoYVfEQcV535ZWoN3XbnH2mi9KhOKVBWD0IpMua0CPIbb9fB4DUV+mgJaLjLcvx/1AN7Q6uBP2/3NPURsGzgzR5llqY0JKxFYZP/J09JIfpG4AfUO2xyxOWH1Kqi6Vj/z7NgVzB</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
  $Home_ = Join-Path $env:ProgramData 'showcase_fleet'
  $AgentDir = Join-Path $Home_ 'agent'
  $StoreDir = Join-Path $Home_ 'store'
  $Utf8 = New-Object Text.UTF8Encoding $false
  $Prog = @{ step = 1; of = 8; name = 'checking the release catalogue'; token = $null; hw = @{} }   # where the install has got to
  function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
  function When { (Get-Date).ToString('d MMM h:mm tt') }
  # one line on the NUC's page (its problems list): only once enrolled, never holds up or stops the install
  function Send-Progress([string]$line) {
    if (-not $Prog.token) { return }
    $b = @{ fleetVersion = ''; modules = @{}; problems = @($line) }; foreach ($k in $Prog.hw.Keys) { $b[$k] = $Prog.hw[$k] }
    try { & $post 'checkin' $b $Prog.token 20 | Out-Null } catch { Say "       (couldn't tell the dashboard: $_)" DarkGray }
  }
  function Set-Step([int]$n, [string]$what, [switch]$Quiet) {
    $Prog.step = $n; $Prog.name = $what
    Say "       Step $n of $($Prog.of): $what"
    if (-not $Quiet) { Send-Progress "Installing, step $n of $($Prog.of): $what ($(When)). If this never changes, the installer stopped here; its log is C:\ProgramData\showcase_fleet\install_log.txt." }
  }
  function Stop-Install([string]$m) {
    Say "`n[FAIL] $m" Red
    Send-Progress "Install stopped at step $($Prog.step) of $($Prog.of), $($Prog.name) ($(When)): $m"
    throw 'stop'
  }
  function Get-AgentLogTail { try { "$(Get-Content (Join-Path $AgentDir 'agent.log') -Tail 1 -ErrorAction Stop)" -replace '^\S+ \S+\s+', '' } catch { 'nothing in the agent log' } }
  # the same as Get-HardwareIds in agent_common.ps1 (keep the two the same)
  function Get-HardwareIds {
    $junk = '^(0*|none|default string|to be filled by o\.e\.m\.|system serial number|not specified|not applicable|n/a|123456789)$'
    $serial = "$((Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber)".Trim()
    if ($serial -match $junk) { $serial = "$((Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).IdentifyingNumber)".Trim() }
    if ($serial -match $junk) { $serial = '' }
    $macs = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { "$($_.PhysicalMediaType) $($_.InterfaceDescription)" -notmatch 'Bluetooth' } |
      Sort-Object ifIndex | ForEach-Object {
        [ordered]@{ name = "$($_.Name)"; mac = $(if ("$($_.PermanentAddress)" -match '^[0-9A-Fa-f]{12}$') { "$($_.PermanentAddress)" } else { "$($_.MacAddress)" })
                    wired = ("$($_.PhysicalMediaType)" -eq '802.3'); up = ("$($_.Status)" -eq 'Up') }
      })
    $main = @(@($macs | Where-Object { $_.wired }) + $macs) | Select-Object -First 1
    @{ serial = $serial; mac = $(if ($main) { $main.mac } else { '' }); macs = @($macs | Select-Object -First 8) }
  }

  # a record of every install, so a run that stops partway always leaves a reason (SYSTEM and admins can read it)
  try { New-Item -ItemType Directory -Force -Path $Home_ | Out-Null; Start-Transcript -Path (Join-Path $Home_ 'install_log.txt') -Append | Out-Null } catch { }
  try {
    Say "`nShowcase Fleet: installing on $env:COMPUTERNAME" White
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Stop-Install 'Open PowerShell as administrator (right-click, Run as administrator) and paste the command again.' }
    $Code = "$code".Trim().ToUpper()
    if ($Code -notmatch '^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$') { Stop-Install 'No install code. Make an install link on the NUC''s page in Showcase Fleet and use its command.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.Security
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # ---- the signed catalogue
    $wc = New-Object Net.WebClient; $wc.Headers['Cache-Control'] = 'no-cache'
    $catBytes = $wc.DownloadData($CatalogueUrl)
    $sig = [Convert]::FromBase64String([Text.Encoding]::ASCII.GetString($wc.DownloadData("$CatalogueUrl.sig")).Trim())
    $rsa = New-Object Security.Cryptography.RSACng
    try { $rsa.FromXmlString($PublicKeyXml); $good = $rsa.VerifyData($catBytes, $sig, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1) } finally { $rsa.Dispose() }
    if (-not $good) { Stop-Install 'The release catalogue failed its signature check. Nothing was installed. Tell Jordan.' }
    $cat = $Utf8.GetString($catBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    Say "[OK]   Release catalogue checked (signed, sequence $($cat.sequence))" Green

    # ---- enrol: the one-time code becomes this NUC's own token
    $guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
    $bios = (Get-CimInstance Win32_BIOS).SerialNumber
    $board = (Get-CimInstance Win32_BaseBoard).SerialNumber
    $sha = [Security.Cryptography.SHA256]::Create()
    $fingerprint = -join ($sha.ComputeHash($Utf8.GetBytes("$guid|$bios|$board")) | ForEach-Object { $_.ToString('x2') }); $sha.Dispose()
    $post = {
      param($op, $body, $token, $timeout = 90)
      $h = @{}; if ($token) { $h.Authorization = "Bearer $token" }
      $body.fingerprint = $fingerprint; $body.hostname = $env:COMPUTERNAME
      try { Invoke-RestMethod -Uri "$($cat.api.TrimEnd('/'))/v1/$op" -Method Post -Headers $h -ContentType 'application/json; charset=utf-8' -Body $Utf8.GetBytes(($body | ConvertTo-Json -Depth 8 -Compress)) -TimeoutSec $timeout -UseBasicParsing }
      catch {
        $m = $_.Exception.Message
        # PowerShell 5.1 keeps the API's answer in ErrorDetails.Message (the response stream has been read by then)
        try { $e = $_.ErrorDetails.Message | ConvertFrom-Json; if ($e.error) { $m = $e.error } } catch { }
        throw $m
      }
    }
    Set-Step 2 'enrolling' -Quiet
    try { $en = & $post 'enrol' @{ code = $Code } $null } catch { Stop-Install "Enrolling didn't work: $_" }
    Say "[OK]   Enrolled as $($en.nucId)" Green
    # from here every step is on the NUC's page in Fleet, with its serial number and MACs
    $Prog.token = $en.token
    try { $Prog.hw = Get-HardwareIds } catch { Say "       (serial and MACs not read: $($_.Exception.Message))" DarkGray }

    foreach ($d in $Home_, $AgentDir, $StoreDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    & icacls.exe $AgentDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /Q | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $AgentDir 'token.dat'), [Security.Cryptography.ProtectedData]::Protect($Utf8.GetBytes($en.token), $null, 'LocalMachine'))
    [IO.File]::WriteAllText((Join-Path $AgentDir 'fleet_public_key.xml'), $PublicKeyXml, [Text.Encoding]::ASCII)
    $state = [ordered]@{ api = $cat.api; catalogueUrl = $CatalogueUrl; catalogueSeq = [long]$cat.sequence; nuc = $en.nuc; nucId = $en.nucId; enrolledAt = (Get-Date).ToString('s') }
    [IO.File]::WriteAllText((Join-Path $AgentDir 'state.json'), ($state | ConvertTo-Json), $Utf8)

    # ---- Fleet core, at this NUC's level's version (this first report also puts step 3 on the NUC's page)
    Set-Step 3 'asking the dashboard which Fleet version to install' -Quiet
    $b3 = @{ fleetVersion = ''; modules = @{}; problems = @("Installing, step 3 of $($Prog.of): $($Prog.name) ($(When)). If this never changes, the installer stopped here; its log is C:\ProgramData\showcase_fleet\install_log.txt.") }
    foreach ($k in $Prog.hw.Keys) { $b3[$k] = $Prog.hw[$k] }
    try { $r = & $post 'checkin' $b3 $en.token } catch { Stop-Install "The dashboard didn't answer: $_" }
    $ver = "$($r.desired.core)"
    if (-not $ver) { Stop-Install "Enrolled, but no Fleet version is set for the $($r.level) level yet. Set it on the Levels page, then run this again with a new install link." }
    $e = $cat.packages.core.$ver
    if (-not $e) { Stop-Install "Fleet $ver isn't in the signed catalogue." }
    Set-Step 4 "downloading Fleet $ver"
    $dir = Join-Path $StoreDir "core\$ver"
    $zip = Join-Path $StoreDir '_download_core.zip'
    try { $wc.DownloadFile("$($cat.packagesBase.TrimEnd('/'))/$($e.path)", $zip) } catch { Stop-Install "The download didn't work (is GitHub reachable from this network?): $($_.Exception.Message)" }
    if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne "$($e.sha256)".ToLowerInvariant()) { Remove-Item $zip -Force; Stop-Install "Fleet $ver failed its sha256 check. Nothing was installed." }
    Set-Step 5 "putting Fleet's files in place"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dir); Remove-Item $zip -Force
    Set-Content (Join-Path $dir '.sha256') $e.sha256 -Encoding ASCII
    # a Fleet folder left by an early trial can have permissions even administrators can't use (trial 3's bug; the
    # uninstaller couldn't remove it): take it back and reset it before copying over it (Brightly, 23 Nov 2026)
    $win = Join-Path $Home_ 'window'
    if (Test-Path $win) {
      & takeown.exe /F $win /R /D Y 2>&1 | Out-Null
      & icacls.exe $win /reset /T /C /Q 2>&1 | Out-Null
    }
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'app\install_window.ps1') -Source $dir 2>&1 | ForEach-Object { "$_" })
    $out | Where-Object { $_ -match '^\[(OK|WARN|FAIL)\]' } | ForEach-Object { Say "       $_" }
    $bad = @($out | Where-Object { $_ -match '^\[FAIL\]' })
    if ($bad.Count) { Stop-Install "Fleet's files couldn't be put in place: $($bad[0] -replace '^\[FAIL\]\s*', ''). The NUC is enrolled; run the installer again after fixing it." }
    Say "[OK]   Fleet $ver installed" Green

    # ---- the agent: its tasks, then the NUC's ticked modules now (the first install doesn't wait for 1am).
    # Trial 14: each pass's answer is kept (it went nowhere before), and a missing task or a failed first check-in
    # stops the install with the reason, instead of saying "Done" over a NUC that will never check in.
    $agent = Join-Path $Home_ 'window\agent\fleet_agent.ps1'
    $runAgent = {
      param($m)
      $o = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agent -Mode $m 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
      $o | Select-Object -Last 5 | ForEach-Object { Say "       $_" DarkGray }
      $LASTEXITCODE -eq 0
    }
    Set-Step 6 "registering the agent's tasks"
    $okSetup = & $runAgent 'setup'
    $missing = @('showcase_fleet_agent_checkin', 'showcase_fleet_agent_install', 'showcase_fleet_agent_check' | Where-Object { -not (Get-ScheduledTask -TaskName $_ -TaskPath '\' -ErrorAction SilentlyContinue) })
    if ($missing.Count) { Stop-Install "The agent's tasks weren't registered ($($missing -join ', ')): $(if (-not $okSetup) { Get-AgentLogTail } else { 'no reason given' }). Without them this NUC never checks in." }
    Say "[OK]   The agent's tasks are registered" Green
    # the agent checks in itself from here: its own report replaces these install lines on the NUC's page
    Set-Step 7 "installing the NUC's ticked modules"
    foreach ($m in 'install', 'check') { if (-not (& $runAgent $m)) { Say "[WARN] The agent's $m pass stopped: $(Get-AgentLogTail). The 1am pass tries again." Yellow } }
    Set-Step 8 'the first check-in from the agent' -Quiet
    if (-not (& $runAgent 'checkin')) { Stop-Install "The agent's first check-in didn't work: $(Get-AgentLogTail)" }
    $st = Get-Content (Join-Path $AgentDir 'state.json') -Raw | ConvertFrom-Json
    $notes = @($st.lastInstall.notes | Where-Object { $_ })
    if ($notes.Count) { $notes | ForEach-Object { Say "       $_" } } else { Say '       No modules ticked yet: nothing on the NUC changed. Its inventory is on the dashboard.' }
    if ($st.lastNight -and $st.lastNight.result -ne 'ok') { Say "[WARN] Check: $($st.lastNight.result). $($st.lastNight.detail)" Yellow }
    Say "`n[OK]   Done. $($en.nucId) checks in every 15 minutes; changes made on the dashboard go in at 1am." Green
    Say '       The agent log is C:\ProgramData\showcase_fleet\agent\agent.log.'
  } catch {
    if ("$_" -ne 'stop') {
      Say "`n[FAIL] $_" Red
      Send-Progress "Install stopped at step $($Prog.step) of $($Prog.of), $($Prog.name) ($(When)): $_"
    }
  } finally { try { Stop-Transcript | Out-Null } catch { } }
}
