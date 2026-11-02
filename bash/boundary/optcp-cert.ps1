# Keeps a valid operator SSH certificate beside the key: signs a new one through OpenBao
# when fewer than OPTCP_CERT_MIN_LEFT seconds remain. Logs in to Zitadel only when run by
# hand; under ssh (-NoLogin, the Match exec in optcp.windows.sshconfig) it says what to run.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~\.ssh\id_ed25519)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
param([switch]$NoLogin)
$addr = if ($env:BAO_ADDR) { $env:BAO_ADDR } else { 'https://secrets.optcp.com' }
$key = if ($env:OPTCP_SSH_KEY) { $env:OPTCP_SSH_KEY } else { "$HOME\.ssh\id_ed25519" }
$cert = "$key-cert.pub"
$minLeft = if ($env:OPTCP_CERT_MIN_LEFT) { [int]$env:OPTCP_CERT_MIN_LEFT } else { 600 }

function Valid {
    if (-not (Test-Path $cert)) { return $false }
    $m = (ssh-keygen -Lf $cert | Select-String 'Valid: from \S+ to (\S+)').Matches
    return ($m.Count -gt 0 -and ([datetime]$m[0].Groups[1].Value) -gt (Get-Date).AddSeconds($minLeft))
}
if (Valid) { exit 0 }

# ssh evaluates its config twice per connection; the second run waits for the first.
$lock = "$cert.lock"
try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null }
catch {
    $n = 0
    while ((Test-Path $lock) -and $n -lt 60) { Start-Sleep 1; $n++ }
    if (Valid) { exit 0 }
    try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null } catch { exit 0 }
}
try {
    bao token lookup -address $addr *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($NoLogin) {
            [Console]::Error.WriteLine("optcp-cert: OpenBao login needed: bao login -address $addr -method=oidc role=operator")
            exit 0
        }
        bao login -address $addr -method=oidc role=operator | Out-Null
    }
    $signed = bao write -address $addr -field=signed_key optcp-ssh/sign/operator "public_key=@$key.pub"
    if ($LASTEXITCODE -ne 0 -or -not $signed) { exit 1 }
    [IO.File]::WriteAllText($cert, "$signed`n")
    exit 0
} finally {
    Remove-Item -Path $lock -Force -ErrorAction SilentlyContinue
}
