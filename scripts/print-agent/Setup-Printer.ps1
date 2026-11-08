$ErrorActionPreference = 'Stop'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Instale o Node.js LTS antes de configurar o agente.' }
$folder = Join-Path $env:LOCALAPPDATA 'PlanetaLanchesPrint'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
# Keep customer receipts and the scoped token accessible only to this account.
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -Path $folder -AclObject $acl
$config = @{}
$config.supabase_url = (Read-Host 'URL publica do projeto Supabase').Trim().TrimEnd('/')
$config.publishable_key = (Read-Host 'Chave publishable publica (nunca service_role)').Trim()
$config.printer_name = Read-Host 'Nome exato da impressora instalada no Windows'
$config.paper_mm = [int](Read-Host 'Largura do papel em mm (58 ou 80)')
if ($config.paper_mm -notin @(58,80)) { throw 'Largura invalida.' }
$secret = Read-Host 'Credencial gerada em Pedidos online > Impressao automatica' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
  $config.token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if ($config.token -notmatch '^[a-f0-9]{64}$') { throw 'Credencial invalida.' }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $folder 'config.json'), ($config | ConvertTo-Json), $utf8)
} finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $config.Remove('token') }
Write-Host 'Configurado. Execute: node scripts/print-agent/agent.mjs'
Write-Host 'Mantenha o agente aberto e teste primeiro com um pedido controlado.'
