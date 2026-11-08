param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9]{20}$')]
  [string] $ProjectRef,
  [ValidateSet('core', 'online', 'whatsapp', 'all')]
  [string] $Group = 'core'
)

$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  # Explicit allowlist: never deploy the incompatible eco-* contract.
  $functions = @('fast-pass', 'staff-admin', 'integration-status', 'payment-intent', 'checkout-payment')
  if ($Group -in @('online', 'all')) {
    $functions += @('customer-api', 'customer-assistant', 'online-payment-webhook', 'print-agent')
  }
  if ($Group -in @('whatsapp', 'all')) {
    $functions += @('whatsapp-webhook', 'whatsapp-send', 'integration-worker')
  }
  Write-Host "Projeto selecionado: $ProjectRef. Grupo: $Group."
  foreach ($function in $functions) {
    & npx supabase functions deploy $function --project-ref $ProjectRef --use-api
    if ($LASTEXITCODE -ne 0) { throw "Falha ao publicar $function. Publicação interrompida." }
  }
} finally {
  Pop-Location
}
