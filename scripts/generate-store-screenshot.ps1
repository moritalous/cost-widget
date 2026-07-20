# Generates a Store-listing screenshot (1366x768) that mirrors the widget's
# card layout on a Windows 11 Widgets Board-style backdrop. Kept separate from
# generate-assets.ps1, which produces the small in-package preview used by the
# widget picker itself.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot '..\build\store-assets'
New-Item -ItemType Directory -Force $outDir | Out-Null

$bgTop = [System.Drawing.Color]::FromArgb(255, 32, 42, 58)
$bgBottom = [System.Drawing.Color]::FromArgb(255, 18, 22, 30)
$boardBg = [System.Drawing.Color]::FromArgb(235, 32, 32, 36)
$cardBg = [System.Drawing.Color]::FromArgb(255, 44, 44, 48)
$gaugeColor = [System.Drawing.Color]::FromArgb(255, 46, 204, 113)
$subtleColor = [System.Drawing.Color]::FromArgb(255, 160, 160, 165)
$trackColor = [System.Drawing.Color]::FromArgb(255, 70, 70, 76)

function New-RoundedRectPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$Radius)
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $gp.AddArc($X, $Y, $d, $d, 180, 90)
    $gp.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $gp.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $gp.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $gp.CloseFigure()
    return $gp
}

$w = 1366; $h = 768
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'

# Desktop-style vertical gradient backdrop.
$bgRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bgRect, $bgTop, $bgBottom, 90)
$g.FillRectangle($bgBrush, $bgRect)

# Widgets Board panel.
$boardX = 40; $boardY = 40; $boardW = 420; $boardH = 688
$boardPath = New-RoundedRectPath -X $boardX -Y $boardY -W $boardW -H $boardH -Radius 18
$g.FillPath((New-Object System.Drawing.SolidBrush($boardBg)), $boardPath)

$fTitle = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Widgets', $fTitle, [System.Drawing.Brushes]::White, ($boardX + 24), ($boardY + 24))

# The widget card itself, large size, matching Templates/large.json content.
$cardX = $boardX + 24; $cardY = $boardY + 80; $cardW = $boardW - 48; $cardH = 560
$cardPath = New-RoundedRectPath -X $cardX -Y $cardY -W $cardW -H $cardH -Radius 12
$g.FillPath((New-Object System.Drawing.SolidBrush($cardBg)), $cardPath)

$subtleBrush = New-Object System.Drawing.SolidBrush($subtleColor)
$white = [System.Drawing.Brushes]::White
$gaugeBrush = New-Object System.Drawing.SolidBrush($gaugeColor)
$trackBrush = New-Object System.Drawing.SolidBrush($trackColor)
$sepPen = New-Object System.Drawing.Pen($trackColor, 1)

$fSmall = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fBig = New-Object System.Drawing.Font('Segoe UI', 34, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fMid = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fBold = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fBar = New-Object System.Drawing.Font('Segoe UI Symbol', 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$pad = $cardX + 20
$row = $cardY + 20
$g.DrawString('Updated 09:19', $fSmall, $subtleBrush, ($cardX + $cardW - 110), $row)
$g.DrawString('Current block 08:00-13:00', $fSmall, $subtleBrush, $pad, $row)

$row += 26
$g.DrawString('$29.51', $fBig, $white, $pad, $row)
$g.DrawString('3h 41m left', $fSmall, $subtleBrush, ($cardX + $cardW - 100), ($row + 14))

$row += 62
$filledBar = [string]::new([char]0x25B0, 3)
$emptyBar = [string]::new([char]0x25B1, 7)
$g.DrawString($filledBar, $fBar, $gaugeBrush, $pad, $row)
$filledWidth = $g.MeasureString($filledBar, $fBar).Width
$g.DrawString($emptyBar, $fBar, $subtleBrush, ($pad + $filledWidth - 4), $row)

$row += 40
$colW = ($cardW - 40) / 3
$g.DrawString('Burn rate', $fSmall, $subtleBrush, $pad, $row)
$g.DrawString('Projected', $fSmall, $subtleBrush, ($pad + $colW), $row)
$g.DrawString('Tokens', $fSmall, $subtleBrush, ($pad + 2 * $colW), $row)
$row += 20
$g.DrawString('$30.63/h', $fBold, $white, $pad, $row)
$g.DrawString('$142', $fBold, $white, ($pad + $colW), $row)
$g.DrawString('17.3M', $fBold, $white, ($pad + 2 * $colW), $row)

$row += 44
$g.DrawLine($sepPen, $pad, $row, ($cardX + $cardW - 20), $row)
$row += 24

$halfW = ($cardW - 40) / 2
$g.DrawString('Today', $fSmall, $subtleBrush, $pad, $row)
$g.DrawString('This month (2026/07)', $fSmall, $subtleBrush, ($pad + $halfW), $row)
$row += 22
$g.DrawString('$29.51', $fMid, $white, $pad, $row)
$g.DrawString('$810', $fMid, $white, ($pad + $halfW), $row)
$row += 34
$g.DrawString('17.3M tokens', $fSmall, $subtleBrush, $pad, $row)
$g.DrawString('607.0M tokens', $fSmall, $subtleBrush, ($pad + $halfW), $row)

$row += 44
$g.DrawLine($sepPen, $pad, $row, ($cardX + $cardW - 20), $row)
$row += 20
$g.DrawString('By model (this month)', $fSmall, $subtleBrush, $pad, $row)
$row += 24
$modelRows = @(
    @('claude-fable-5', '$649'),
    @('claude-opus-4-8', '$128'),
    @('gpt-5.6-terra', '$3.06')
)
foreach ($m in $modelRows) {
    $g.DrawString($m[0], $fSmall, $subtleBrush, $pad, $row)
    $priceSize = $g.MeasureString($m[1], $fBold)
    $g.DrawString($m[1], $fBold, $white, ($cardX + $cardW - 20 - $priceSize.Width), ($row - 2))
    $row += 26
}

$footer = 'cost widget powered by ccusage'
$fFooter = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$footerSize = $g.MeasureString($footer, $fFooter)
$g.DrawString($footer, $fFooter, $subtleBrush, ($cardX + ($cardW - $footerSize.Width) / 2), ($cardY + $cardH - 30))

# Right-side marketing text.
$fHeadline = New-Object System.Drawing.Font('Segoe UI', 40, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fSub = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$textX = $boardX + $boardW + 60
$g.DrawString("Your Claude Code costs,`non the Windows Widgets Board.", $fHeadline, $white, $textX, 260)
$g.DrawString('Win+W, and you know exactly where you stand.', $fSub, $subtleBrush, $textX, 380)

$g.Dispose()
$dest = Join-Path $outDir 'store-screenshot-1.png'
$bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "generated: $dest"
