# hipbass marketing PC (5800X3D / RTX 3070) remote-connect setup.
# Contains ONLY a public key. No private key, token or password. Run in an ADMIN PowerShell:  irm <URL> | iex
# What it does: OpenSSH server (auto start), key login only, firewall port 22 only from Tailscale (100.64.0.0/10),
# no sleep (monitor may turn off), C:\hipbass_mkt folder, one Korean result line. It does NOT touch GPU drivers.
function K($s){ [regex]::Unescape($s) }
function Invoke-HipbassSetup {
  $ErrorActionPreference = 'Stop'
  $pub   = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOA56IgZBNBaEjGVRpHnmVte0FilmKd6QSpHXO5m8nqL hipbass_pc3070'
  $topic = 'hbpc-8b2603c7b0fd6002de1b'
  $cur = 'start'
  $info = @{}
  try {
    $cur = 'admin'
    $pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
      Write-Host (K '[\uD799\uBCA0\uC774\uC2A4] \uAD00\uB9AC\uC790 PowerShell \uC774 \uC544\uB2D9\uB2C8\uB2E4. \uC2DC\uC791 \uBC84\uD2BC \uC6B0\uD074\uB9AD > "\uD130\uBBF8\uB110(\uAD00\uB9AC\uC790)" \uB85C \uB2E4\uC2DC \uC5F4\uACE0 \uD55C \uC904\uC744 \uB2E4\uC2DC \uBD99\uC5EC\uB123\uC73C\uC138\uC694.') -ForegroundColor Red
      return
    }
    $u = $null
    try { $u = (Get-CimInstance Win32_ComputerSystem).UserName } catch {}
    if (-not $u) { $u = "$env:USERDOMAIN\$env:USERNAME" }
    $uname = $u.Split('\')[-1]
    $info.user = $uname
    $info.host = $env:COMPUTERNAME

    $cur = 'openssh-install'
    $sv = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $sv) {
      try { Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null } catch { $info.capErr = $_.Exception.Message }
      $sv = Get-Service sshd -ErrorAction SilentlyContinue
    }
    if (-not $sv -and (Get-Command winget -ErrorAction SilentlyContinue)) {
      winget install --id Microsoft.OpenSSH.Beta -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
      $sv = Get-Service sshd -ErrorAction SilentlyContinue
    }
    if (-not $sv) { throw 'sshd service missing' }

    $cur = 'openssh-start'
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    Start-Sleep -Seconds 2
    & sc.exe failure sshd reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    # sshd_config: key login only (password login off). The default admin-key block stays as is.
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path $cfg) {
      $t = [IO.File]::ReadAllText($cfg)
      if ($t -match '(?m)^\s*#?\s*PasswordAuthentication\s+\S+') { $t = [regex]::Replace($t, '(?m)^\s*#?\s*PasswordAuthentication\s+\S+', 'PasswordAuthentication no') }
      else { $t = "PasswordAuthentication no`r`n" + $t }
      if ($t -match '(?m)^\s*#?\s*PubkeyAuthentication\s+\S+') { $t = [regex]::Replace($t, '(?m)^\s*#?\s*PubkeyAuthentication\s+\S+', 'PubkeyAuthentication yes') }
      [IO.File]::WriteAllText($cfg, $t, (New-Object Text.UTF8Encoding($false)))
    }

    $cur = 'key'
    $enc = New-Object Text.UTF8Encoding($false)
    $ak = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    $keep = @()
    if (Test-Path $ak) { $keep = @(Get-Content $ak | Where-Object { $_ -and ($_ -notmatch 'hipbass_pc3070') }) }
    [IO.File]::WriteAllText($ak, ((@($keep) + $pub) -join "`r`n") + "`r`n", $enc)
    & icacls.exe $ak /inheritance:r /grant '*S-1-5-18:(F)' /grant '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'icacls failed' }
    # same key for a non-admin login (per-user file), so it also works if this account is not an administrator
    $udir = Join-Path $env:SystemDrive "Users\$uname\.ssh"
    if (Test-Path (Join-Path $env:SystemDrive "Users\$uname")) {
      New-Item -ItemType Directory -Force -Path $udir | Out-Null
      $uak = Join-Path $udir 'authorized_keys'
      $k2 = @()
      if (Test-Path $uak) { $k2 = @(Get-Content $uak | Where-Object { $_ -and ($_ -notmatch 'hipbass_pc3070') }) }
      [IO.File]::WriteAllText($uak, ((@($k2) + $pub) -join "`r`n") + "`r`n", $enc)
      & icacls.exe $uak /inheritance:r /grant '*S-1-5-18:(F)' /grant '*S-1-5-32-544:(F)' /grant "${u}:(F)" | Out-Null
    }

    $cur = 'firewall'
    Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    Get-NetFirewallRule -Name 'hipbass-ssh-tailscale' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name 'hipbass-ssh-tailscale' -DisplayName 'hipbass ssh (Tailscale only)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
    Restart-Service sshd
    Start-Sleep -Seconds 2

    $cur = 'power'
    & powercfg.exe /change standby-timeout-ac 0
    & powercfg.exe /change standby-timeout-dc 0
    & powercfg.exe /change hibernate-timeout-ac 0
    & powercfg.exe /change hibernate-timeout-dc 0
    & powercfg.exe /change disk-timeout-ac 0
    & powercfg.exe /change monitor-timeout-ac 10

    $cur = 'folder'
    foreach ($d in 'C:\hipbass_mkt', 'C:\hipbass_mkt\jobs', 'C:\hipbass_mkt\bin', 'C:\hipbass_mkt\logs', 'C:\hipbass_mkt\tmp') { New-Item -ItemType Directory -Force -Path $d | Out-Null }

    $cur = 'check'
    $ok = (Get-Service sshd).Status -eq 'Running'
    $listen = $false
    try { $listen = [bool](Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) } catch {}
    $tsip = ''
    try {
      $ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
      if (-not $ts -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $ts = "$env:ProgramFiles\Tailscale\tailscale.exe" }
      if ($ts) { $tsip = [string](& $ts ip -4 2>$null | Select-Object -First 1) }
    } catch {}
    $gpu = ''; $ram = ''
    try { $gpu = ((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ' / ') } catch {}
    try { $ram = [string][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch {}
    $info.ts = $tsip
    $note = "setup=$(if($ok -and $listen){'OK'}else{'CHECK'}) user=$uname host=$env:COMPUTERNAME tailscale_ip=$tsip sshd=$((Get-Service sshd).Status) port22=$listen gpu=$gpu ram_gb=$ram os=$([Environment]::OSVersion.VersionString)"
    try { Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$topic" -Body ([Text.Encoding]::UTF8.GetBytes($note)) -TimeoutSec 15 | Out-Null } catch {}
    try { [IO.File]::WriteAllText('C:\hipbass_mkt\logs\setup_result.txt', $note + "`r`n", $enc) } catch {}

    if ($ok -and $listen -and $tsip) {
      Write-Host ((K '[\uD799\uBCA0\uC774\uC2A4] \uC124\uCE58 \uC644\uB8CC. \uC5F0\uACB0 \uC8FC\uC18C ') + $tsip + (K ' / \uC0AC\uC6A9\uC790 ') + $uname + (K ' . \uC774\uC81C \uC544\uBB34\uAC83\uB3C4 \uC548 \uD558\uC154\uB3C4 \uB429\uB2C8\uB2E4. \uC774 \uCC3D\uC740 \uB2EB\uC544\uB3C4 \uB429\uB2C8\uB2E4.')) -ForegroundColor Green
    } elseif ($ok -and $listen) {
      Write-Host (K '[\uD799\uBCA0\uC774\uC2A4] \uC124\uCE58\uB294 \uB05D\uB0AC\uC9C0\uB9CC Tailscale \uC774 \uC544\uC9C1 \uC5C6\uAC70\uB098 \uB85C\uADF8\uC778\uC774 \uC548 \uB410\uC2B5\uB2C8\uB2E4. Tailscale \uC744 \uC124\uCE58\uD558\uACE0 \uAC19\uC740 \uACC4\uC815\uC73C\uB85C \uB85C\uADF8\uC778\uD55C \uB4A4 \uD55C \uC904\uC744 \uB2E4\uC2DC \uBD99\uC5EC\uB123\uC5B4 \uC8FC\uC138\uC694.') -ForegroundColor Yellow
    } else {
      Write-Host (K '[\uD799\uBCA0\uC774\uC2A4] \uC124\uCE58\uB294 \uD588\uC9C0\uB9CC \uC6D0\uACA9 \uC811\uC18D \uC11C\uBE44\uC2A4(sshd)\uAC00 \uCF1C\uC9C0\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uC774 \uD654\uBA74\uC744 \uC0AC\uC9C4 \uCC0D\uC5B4 \uBCF4\uB0B4\uC8FC\uC138\uC694.') -ForegroundColor Yellow
    }
  }
  catch {
    $msg = $_.Exception.Message
    Write-Host ((K '[\uD799\uBCA0\uC774\uC2A4] \uC2E4\uD328: \uB2E8\uACC4 ') + $cur + (K ' - \uC774 \uD654\uBA74\uC744 \uC0AC\uC9C4 \uCC0D\uC5B4 \uBCF4\uB0B4\uC8FC\uC138\uC694. ') + $msg) -ForegroundColor Red
    try { Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$topic" -Body ([Text.Encoding]::UTF8.GetBytes("setup=FAILED step=$cur err=$msg host=$env:COMPUTERNAME")) -TimeoutSec 15 | Out-Null } catch {}
  }
}
Invoke-HipbassSetup
