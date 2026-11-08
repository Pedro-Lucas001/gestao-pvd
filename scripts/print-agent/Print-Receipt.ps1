param(
  [Parameter(Mandatory = $true)][string] $ReceiptPath,
  [Parameter(Mandatory = $true)][string] $PrinterName,
  [ValidateSet(58,80)][int] $PaperMm = 80
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$document = New-Object System.Drawing.Printing.PrintDocument
$font = New-Object System.Drawing.Font('Consolas', 8)
try {
  $document.PrinterSettings.PrinterName = $PrinterName
  if (-not $document.PrinterSettings.IsValid) { throw 'Impressora nao instalada ou indisponivel.' }
  $document.DocumentName = 'Planeta Lanches - Pedido'
  $document.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $document.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize('Comanda', [int]($PaperMm / 25.4 * 100), 1100)
  $document.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(8, 8, 8, 8)
  $script:receiptLines = [System.IO.File]::ReadAllLines($ReceiptPath, [System.Text.Encoding]::UTF8)
  $script:receiptIndex = 0
  $document.add_PrintPage({
    param($sender, $event)
    $lineHeight = $font.GetHeight($event.Graphics) + 2
    $y = $event.MarginBounds.Top
    while ($script:receiptIndex -lt $script:receiptLines.Length -and $y + $lineHeight -le $event.MarginBounds.Bottom) {
      $event.Graphics.DrawString($script:receiptLines[$script:receiptIndex], $font, [System.Drawing.Brushes]::Black, [single]$event.MarginBounds.Left, [single]$y)
      $script:receiptIndex++
      $y += $lineHeight
    }
    $event.HasMorePages = $script:receiptIndex -lt $script:receiptLines.Length
  })
  $document.Print()
} finally { $font.Dispose(); $document.Dispose() }
