<#
.SYNOPSIS
    AVIファイルを解析し、各フレームの指定座標の画素値をCSVに出力します。

.DESCRIPTION
    - ffmpegをwingetでインストール（未インストールの場合）
    - AVIファイルの各フレームをJPEGに変換
    - 各フレームの指定座標(X, Y)のRGB画素値を取得
    - 結果をCSVファイルに出力

.PARAMETER AviFile
    解析対象のAVIファイルパス

.PARAMETER CoordX
    画素値を取得するX座標（ピクセル）

.PARAMETER CoordY
    画素値を取得するY座標（ピクセル）

.PARAMETER OutputCsv
    出力先CSVファイルパス（省略時: 入力ファイル名_pixels.csv）

.PARAMETER FrameDir
    フレームJPEGの出力ディレクトリ（省略時: 一時ディレクトリを使用）

.PARAMETER KeepFrames
    フレームJPEGを処理後も保持する場合に指定

.EXAMPLE
    .\analyze_avi.ps1 -AviFile "C:\videos\sample.avi" -CoordX 100 -CoordY 200

.EXAMPLE
    .\analyze_avi.ps1 -AviFile "sample.avi" -CoordX 320 -CoordY 240 -OutputCsv "result.csv" -KeepFrames
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "解析対象のAVIファイルパス")]
    [string]$AviFile,

    [Parameter(Mandatory = $true, HelpMessage = "画素値を取得するX座標")]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$CoordX,

    [Parameter(Mandatory = $true, HelpMessage = "画素値を取得するY座標")]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$CoordY,

    [Parameter(HelpMessage = "出力先CSVファイルパス")]
    [string]$OutputCsv = "",

    [Parameter(HelpMessage = "フレームJPEGの出力ディレクトリ")]
    [string]$FrameDir = "",

    [Parameter(HelpMessage = "フレームJPEGを処理後も保持する")]
    [switch]$KeepFrames
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# System.Drawing を一度だけロード
Add-Type -AssemblyName System.Drawing

# ----------------------------------------------------------------
# ffmpeg インストール確認 / インストール
# ----------------------------------------------------------------
function Install-Ffmpeg {
    $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpegCmd) {
        Write-Host "[INFO] ffmpeg は既にインストールされています: $($ffmpegCmd.Source)"
        return
    }

    Write-Host "[INFO] ffmpeg が見つかりません。winget でインストールします..."

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        throw "winget が見つかりません。Windows Package Manager (winget) をインストールしてください。"
    }

    winget install --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg のインストールに失敗しました (終了コード: $LASTEXITCODE)。"
    }

    # PATH を現在のセッションに反映
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpegCmd) {
        throw "ffmpeg インストール後もコマンドが見つかりません。シェルを再起動してください。"
    }

    Write-Host "[INFO] ffmpeg のインストールが完了しました: $($ffmpegCmd.Source)"
}

# ----------------------------------------------------------------
# AVIファイルの各フレームをJPEGに変換
# ----------------------------------------------------------------
function Export-Frames {
    param(
        [string]$InputFile,
        [string]$OutputDir
    )

    Write-Host "[INFO] フレームをJPEGに変換中: $InputFile -> $OutputDir"

    $framePattern = Join-Path $OutputDir "frame_%06d.jpg"
    $ffmpegOutput = & ffmpeg -i $InputFile -vsync 0 -q:v 2 $framePattern 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] ffmpeg 出力:"
        $ffmpegOutput | ForEach-Object { Write-Host "  $_" }
        throw "ffmpeg によるフレーム抽出に失敗しました (終了コード: $LASTEXITCODE)。"
    }

    $frames = Get-ChildItem -Path $OutputDir -Filter "frame_*.jpg" | Sort-Object Name
    Write-Host "[INFO] 抽出フレーム数: $($frames.Count)"
    return $frames
}

# ----------------------------------------------------------------
# JPEGファイルから指定座標のRGB画素値を取得
# ----------------------------------------------------------------
function Get-PixelValue {
    param(
        [string]$ImagePath,
        [int]$X,
        [int]$Y
    )

    $bitmap = [System.Drawing.Bitmap]::new($ImagePath)
    try {
        if ($X -lt 0 -or $Y -lt 0 -or $X -ge $bitmap.Width -or $Y -ge $bitmap.Height) {
            throw "座標 ($X, $Y) が画像サイズ ($($bitmap.Width) x $($bitmap.Height)) の範囲外です。座標は 0 以上かつ画像サイズ未満で指定してください。"
        }
        $pixel = $bitmap.GetPixel($X, $Y)
        return @{
            R = [int]$pixel.R
            G = [int]$pixel.G
            B = [int]$pixel.B
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

# ----------------------------------------------------------------
# ffmpegでフレームのタイムスタンプ一覧を取得
# ----------------------------------------------------------------
function Get-FrameTimestamps {
    param([string]$InputFile)

    Write-Host "[INFO] タイムスタンプ情報を取得中..."
    $output = & ffprobe -v quiet -select_streams v:0 -show_entries frame=pts_time -of csv=p=0 $InputFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "ffprobe によるタイムスタンプ取得に失敗しました。タイムスタンプは計算値を使用します。"
        return $null
    }

    $timestamps = $output | Where-Object { $_ -match '^\d' } | ForEach-Object { [double]$_ }
    return $timestamps
}

# ----------------------------------------------------------------
# メイン処理
# ----------------------------------------------------------------

# 1. ffmpeg インストール確認
Install-Ffmpeg

# 2. 入力ファイルの確認
$AviFile = Resolve-Path $AviFile -ErrorAction Stop | Select-Object -ExpandProperty Path
Write-Host "[INFO] 解析対象: $AviFile"

# 3. 出力先CSVパスの決定
if ($OutputCsv -eq "") {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($AviFile)
    $OutputCsv = Join-Path (Split-Path $AviFile -Parent) "${baseName}_pixels.csv"
}
Write-Host "[INFO] CSV出力先: $OutputCsv"

# 4. フレーム出力ディレクトリの準備
$tempDir = $false
if ($FrameDir -eq "") {
    $FrameDir = Join-Path $env:TEMP ("analyze_avi_" + [System.IO.Path]::GetRandomFileName())
    $tempDir = $true
}

if (-not (Test-Path $FrameDir)) {
    New-Item -ItemType Directory -Path $FrameDir | Out-Null
}
Write-Host "[INFO] フレーム出力先: $FrameDir"

try {
    # 5. フレームをJPEGに変換
    $frames = Export-Frames -InputFile $AviFile -OutputDir $FrameDir

    if ($frames.Count -eq 0) {
        throw "フレームが1枚も抽出されませんでした。AVIファイルを確認してください。"
    }

    # 6. タイムスタンプ取得
    $timestamps = Get-FrameTimestamps -InputFile $AviFile

    # 7. 各フレームの画素値を取得してCSVに出力
    Write-Host "[INFO] 画素値を取得してCSVに出力中..."

    $csvRows = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($i = 0; $i -lt $frames.Count; $i++) {
        $frame = $frames[$i]
        $frameNumber = $i + 1

        # タイムスタンプ（ffprobeで取得できた場合はその値、できなかった場合はフレーム名から推定）
        if ($timestamps -and $i -lt $timestamps.Count) {
            $timestamp = [math]::Round($timestamps[$i], 6)
        }
        else {
            $timestamp = ""
        }

        $pixel = Get-PixelValue -ImagePath $frame.FullName -X $CoordX -Y $CoordY

        $row = [PSCustomObject]@{
            FrameNumber = $frameNumber
            FileName    = $frame.Name
            Timestamp   = $timestamp
            X           = $CoordX
            Y           = $CoordY
            R           = $pixel.R
            G           = $pixel.G
            B           = $pixel.B
        }
        $csvRows.Add($row)

        if ($frameNumber % 100 -eq 0) {
            Write-Host "[INFO] 処理済み: $frameNumber / $($frames.Count) フレーム"
        }
    }

    # 8. CSV書き出し（BOM付きUTF-8: Windows PowerShell 5.1 では UTF8 = BOM付き）
    # PowerShell Core (7+) で BOM付きUTF-8 にする場合は -Encoding utf8BOM を使用してください。
    $csvRows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

    Write-Host "[INFO] 完了。$($csvRows.Count) フレームの結果を出力しました: $OutputCsv"
}
finally {
    # 9. 一時ディレクトリの削除（KeepFramesが指定されていない場合）
    if ($tempDir -and -not $KeepFrames -and (Test-Path $FrameDir)) {
        Remove-Item -Path $FrameDir -Recurse -Force
        Write-Host "[INFO] 一時フレームディレクトリを削除しました: $FrameDir"
    }
    elseif ($KeepFrames) {
        Write-Host "[INFO] フレームJPEGを保持しています: $FrameDir"
    }
}
