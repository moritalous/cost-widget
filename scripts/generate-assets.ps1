# Generates widget PNG assets (icons and the picker screenshot).
# Depends only on System.Drawing, which ships with Windows.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$assetsDir = Join-Path $PSScriptRoot '..\src\CostWidgetProvider\Assets'
New-Item -ItemType Directory -Force $assetsDir | Out-Null

$bgColor = [System.Drawing.Color]::FromArgb(255, 27, 36, 48)      # deep navy
$trackColor = [System.Drawing.Color]::FromArgb(255, 62, 74, 90)   # gauge track
$gaugeColor = [System.Drawing.Color]::FromArgb(255, 46, 204, 113) # money green
$cardBg = [System.Drawing.Color]::FromArgb(255, 38, 38, 42)

function New-RoundedRectPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius)
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $gp.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $gp.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $gp.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $gp.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $gp.CloseFigure()
    return $gp
}

# Icon: a gauge (dashboard) ring with a dollar sign in the center.
function New-Icon {
    param([int]$Size, [string]$Path)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)

    $r = [Math]::Max(3, [int]($Size * 0.2))
    $gp = New-RoundedRectPath -Rect (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)) -Radius $r
    $g.FillPath((New-Object System.Drawing.SolidBrush($bgColor)), $gp)

    $penWidth = [Math]::Max(2.0, $Size * 0.09)
    $inset = ($penWidth / 2) + ($Size * 0.14)
    $side = $Size - (2 * $inset)
    $arcRect = New-Object System.Drawing.RectangleF($inset, $inset, $side, $side)

    # Speedometer-style arc: 240 degrees of track, ~70% filled.
    $trackPen = New-Object System.Drawing.Pen($trackColor, $penWidth)
    $trackPen.StartCap = 'Round'; $trackPen.EndCap = 'Round'
    $g.DrawArc($trackPen, $arcRect, 150, 240)
    $gaugePen = New-Object System.Drawing.Pen($gaugeColor, $penWidth)
    $gaugePen.StartCap = 'Round'; $gaugePen.EndCap = 'Round'
    $g.DrawArc($gaugePen, $arcRect, 150, 168)

    $fontSize = [Math]::Max(8, [int]($Size * 0.34))
    $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('$', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, ($Size * 0.06), $Size, $Size)), $sf)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "generated: $Path"
}

# Screenshot: mirrors the current medium (full) card layout in English.
function New-Screenshot {
    param([string]$Path)

    $w = 500; $h = 400
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear($cardBg)

    $subtle = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 160, 160, 165))
    $white = [System.Drawing.Brushes]::White
    $gaugeBrush = New-Object System.Drawing.SolidBrush($gaugeColor)
    $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 70, 70, 76))
    $sepPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 70, 70, 76), 1)

    $fSmall = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fBig = New-Object System.Drawing.Font('Segoe UI', 42, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fMid = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fBold = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

    $g.DrawString('Updated 09:19', $fSmall, $subtle, 390, 16)
    $g.DrawString('Current block 08:00-13:00', $fSmall, $subtle, 24, 42)
    $g.DrawString('$29.51', $fBig, $white, 18, 62)
    $g.DrawString('3h 41m left', $fSmall, $subtle, 396, 92)

    # Same glyph bar as the actual widget (TextBlock color "good" renders green).
    $fBar = New-Object System.Drawing.Font('Segoe UI Symbol', 17, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $filledBar = [string]::new([char]0x25B0, 3)
    $emptyBar = [string]::new([char]0x25B1, 7)
    $g.DrawString($filledBar, $fBar, $gaugeBrush, 22, 118)
    $filledWidth = $g.MeasureString($filledBar, $fBar).Width
    $g.DrawString($emptyBar, $fBar, $subtle, (22 + $filledWidth - 4), 118)

    $g.DrawString('Burn rate', $fSmall, $subtle, 24, 148)
    $g.DrawString('$30.63/h', $fBold, $white, 22, 168)
    $g.DrawString('Projected', $fSmall, $subtle, 190, 148)
    $g.DrawString('$142', $fBold, $white, 188, 168)
    $g.DrawString('Tokens', $fSmall, $subtle, 356, 148)
    $g.DrawString('17.3M', $fBold, $white, 354, 168)

    $g.DrawLine($sepPen, 24, 210, 476, 210)

    $g.DrawString('Today', $fSmall, $subtle, 24, 226)
    $g.DrawString('$29.51', $fMid, $white, 20, 248)
    $g.DrawString('17.3M tokens', $fSmall, $subtle, 24, 284)
    $g.DrawString('This month (2026/07)', $fSmall, $subtle, 260, 226)
    $g.DrawString('$810', $fMid, $white, 256, 248)
    $g.DrawString('607.0M tokens', $fSmall, $subtle, 260, 284)

    $footer = 'cost widget powered by ccusage'
    $footerSize = $g.MeasureString($footer, $fSmall)
    $footerX = ($w - $footerSize.Width) / 2
    $g.DrawString($footer, $fSmall, $subtle, $footerX, 368)

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "generated: $Path"
}

New-Icon -Size 50  -Path (Join-Path $assetsDir 'StoreLogo.png')
New-Icon -Size 44  -Path (Join-Path $assetsDir 'Square44x44Logo.png')
New-Icon -Size 150 -Path (Join-Path $assetsDir 'Square150x150Logo.png')
New-Icon -Size 96  -Path (Join-Path $assetsDir 'WidgetIcon.png')
New-Screenshot -Path (Join-Path $assetsDir 'Screenshot.png')
