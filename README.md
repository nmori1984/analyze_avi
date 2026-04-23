# analyze_avi

Windows 10 上で AVI ファイルを解析し、各フレームの指定座標の画素値（RGB）を CSV に出力する PowerShell スクリプトです。

## 機能

- `winget` を使って **ffmpeg** を自動インストール（未インストールの場合）
- AVI ファイルの各フレームを **JPEG** に変換（ffmpeg 使用）
- 各フレームの指定座標 **(X, Y)** の **RGB 画素値** を取得
- フレーム番号・ファイル名・タイムスタンプ・座標・RGB 値を **CSV ファイル** に出力

## 動作環境

| 要件 | バージョン |
|------|-----------|
| OS | Windows 10 / 11 |
| PowerShell | 5.1 以上 |
| winget | 最新版（Windows Package Manager） |
| ffmpeg | winget で自動インストール |

## 使い方

### 基本的な使い方

```powershell
.\analyze_avi.ps1 -AviFile "C:\videos\sample.avi" -CoordX 100 -CoordY 200
```

### パラメータ一覧

| パラメータ | 必須 | 説明 | デフォルト |
|-----------|------|------|-----------|
| `-AviFile` | ✓ | 解析対象の AVI ファイルパス | — |
| `-CoordX` | ✓ | 画素値を取得する X 座標（ピクセル） | — |
| `-CoordY` | ✓ | 画素値を取得する Y 座標（ピクセル） | — |
| `-OutputCsv` | — | 出力先 CSV ファイルパス | `<入力ファイル名>_pixels.csv` |
| `-FrameDir` | — | フレーム JPEG の出力ディレクトリ | 一時ディレクトリ（自動削除） |
| `-KeepFrames` | — | 処理後もフレーム JPEG を保持する | 保持しない |

### 使用例

```powershell
# 基本（CSVは sample_pixels.csv に出力）
.\analyze_avi.ps1 -AviFile "sample.avi" -CoordX 320 -CoordY 240

# CSV 出力先を指定
.\analyze_avi.ps1 -AviFile "sample.avi" -CoordX 320 -CoordY 240 -OutputCsv "result.csv"

# フレーム JPEG を保持してカスタムディレクトリに出力
.\analyze_avi.ps1 -AviFile "sample.avi" -CoordX 0 -CoordY 0 -FrameDir "C:\frames" -KeepFrames
```

## CSV 出力形式

| 列名 | 説明 |
|------|------|
| `FrameNumber` | フレーム番号（1 始まり） |
| `FileName` | フレーム JPEG のファイル名 |
| `Timestamp` | タイムスタンプ（秒、ffprobe で取得） |
| `X` | 指定 X 座標 |
| `Y` | 指定 Y 座標 |
| `R` | 赤チャンネル値（0–255） |
| `G` | 緑チャンネル値（0–255） |
| `B` | 青チャンネル値（0–255） |

### CSV 出力例

```
"FrameNumber","FileName","Timestamp","X","Y","R","G","B"
"1","frame_000001.jpg","0.000000","320","240","128","64","192"
"2","frame_000002.jpg","0.033333","320","240","130","65","190"
...
```

## 処理フロー

```
1. ffmpeg インストール確認（未インストールの場合は winget で自動インストール）
2. AVI ファイルの各フレームを JPEG に変換（ffmpeg）
3. ffprobe でタイムスタンプ情報を取得
4. 各フレーム JPEG から指定座標の RGB 画素値を取得（System.Drawing）
5. CSV ファイルに結果を出力
6. 一時フレームディレクトリを削除（-KeepFrames 未指定の場合）
```

## 注意事項

- 実行ポリシーにより PowerShell スクリプトの実行がブロックされる場合は、以下を実行してください。
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```
- 指定座標が画像サイズを超える場合はエラーになります。AVI ファイルの解像度を確認してください。
- ffmpeg のインストール後、PATH が反映されない場合はシェルを再起動してください。