# Keeps a valid operator SSH certificate beside the key and a live Boundary token in the
# keyring: signs a new certificate through OpenBao when fewer than OPTCP_CERT_MIN_LEFT seconds
# remain, and logs in to Zitadel (OpenBao or Boundary) when that login is gone. Run by ssh
# (the Match exec in optcp.windows.sshconfig) or by hand; -NoLogin prints the login commands
# instead of running them.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   BOUNDARY_ADDR       Boundary           (default https://access.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~\.ssh\id_ed25519)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
param([switch]$NoLogin)
$addr = if ($env:BAO_ADDR) { $env:BAO_ADDR } else { 'https://secrets.optcp.com' }
$baddr = if ($env:BOUNDARY_ADDR) { $env:BOUNDARY_ADDR } else { 'https://access.optcp.com' }
$key = if ($env:OPTCP_SSH_KEY) { $env:OPTCP_SSH_KEY } else { "$HOME\.ssh\id_ed25519" }
$cert = "$key-cert.pub"
$minLeft = if ($env:OPTCP_CERT_MIN_LEFT) { [int]$env:OPTCP_CERT_MIN_LEFT } else { 600 }

function Valid {
    if (-not (Test-Path $cert)) { return $false }
    $m = (ssh-keygen -Lf $cert | Select-String 'Valid: from \S+ to (\S+)').Matches
    return ($m.Count -gt 0 -and ([datetime]$m[0].Groups[1].Value) -gt (Get-Date).AddSeconds($minLeft))
}
# The stored token is at_<id>_<secret>; reading itself succeeds only while the controller still
# holds it, so a stale, expired or purged token fails here instead of at boundary connect.
function BoundaryValid {
    $t = boundary config get-token 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $t) { return $false }
    $id = (($t -split '_')[0..1]) -join '_'
    boundary auth-tokens read -addr $baddr -id $id *> $null
    return ($LASTEXITCODE -eq 0)
}
function Ready { return ((Valid) -and (BoundaryValid)) }
if (Ready) { exit 0 }

# ssh evaluates its config twice per connection; the second run waits for the first, which
# may be waiting on a browser login.
$lock = "$cert.lock"
try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null }
catch {
    $n = 0
    while ((Test-Path $lock) -and $n -lt 300) { Start-Sleep 1; $n++ }
    if (Ready) { exit 0 }
    try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null } catch { exit 0 }
}
try {
    if (-not (BoundaryValid)) {
        if ($NoLogin) {
            [Console]::Error.WriteLine("optcp-cert: Boundary login needed: boundary authenticate oidc -addr $baddr")
        } else {
            boundary authenticate oidc -addr $baddr | Out-Null
            if ($LASTEXITCODE -ne 0) { exit 1 }
        }
    }
    if (Valid) { exit 0 }
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
