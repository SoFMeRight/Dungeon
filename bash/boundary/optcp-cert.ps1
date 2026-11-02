# Keeps a valid operator SSH certificate beside the key: signs a new one through OpenBao
# when fewer than OPTCP_CERT_MIN_LEFT seconds remain, and logs in to Zitadel only when
# the OpenBao token is gone. Run by ssh (Match exec in optcp.windows.sshconfig) or by hand.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~\.ssh\id_ed25519_sk)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
$addr = if ($env:BAO_ADDR) { $env:BAO_ADDR } else { 'https://secrets.optcp.com' }
$key = if ($env:OPTCP_SSH_KEY) { $env:OPTCP_SSH_KEY } else { "$HOME\.ssh\id_ed25519_sk" }
$cert = "$key-cert.pub"
$minLeft = if ($env:OPTCP_CERT_MIN_LEFT) { [int]$env:OPTCP_CERT_MIN_LEFT } else { 600 }

if (Test-Path $cert) {
    $m = (ssh-keygen -Lf $cert | Select-String 'Valid: from \S+ to (\S+)').Matches
    if ($m.Count -gt 0 -and ([datetime]$m[0].Groups[1].Value) -gt (Get-Date).AddSeconds($minLeft)) { exit 0 }
}
bao token lookup -address $addr *> $null
if ($LASTEXITCODE -ne 0) { bao login -address $addr -method=oidc role=operator | Out-Null }
$signed = bao write -address $addr -field=signed_key optcp-ssh/sign/operator "public_key=@$key.pub"
if ($LASTEXITCODE -ne 0 -or -not $signed) { exit 1 }
[IO.File]::WriteAllText($cert, "$signed`n")
exit 0
