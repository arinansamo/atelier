# atelier check - 構成の異常を検出して報告する（自動修正はしない）
# -Strict を付けると、意図的かもしれない細かい点まで一覧する（check-strict.bat から使う）
param([string]$ToolDir, [switch]$Strict)

$ErrorActionPreference = 'Stop'

$findings = New-Object 'System.Collections.Generic.List[object]'
$imageExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.psd', '.tif', '.tiff')
$workNames = @{}

function Add-Finding {
    param([string]$Category, [string]$Name)
    $findings.Add([pscustomobject]@{ Category = $Category; Name = $Name })
}

# works 配下を再帰的に歩く。YYYYMMDD- で始まるフォルダは作品として検査し、
# それ以外はグループとして中に潜る。ただし .clip を直接持つものは
# 「名前が規則外の作品フォルダ」とみなして報告する
function Invoke-GenreScan {
    param([string]$Dir, [string]$Rel, [int]$Depth)

    # グループの階層に直接置かれた .clip・画像は迷子。作品フォルダに入っていないのは無条件におかしい。
    # それ以外のファイル（メモ等）は意図的かもしれないので厳密モードのみ。
    # Windows が勝手に作る desktop.ini 等は無視する
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File | Sort-Object Name)) {
        if (@('desktop.ini', 'thumbs.db') -contains $f.Name.ToLowerInvariant()) { continue }
        $fileRel = if ($Rel -eq '') { "works\$($f.Name)" } else { "works\$Rel\$($f.Name)" }
        $ext = $f.Extension.ToLower()
        if ($ext -eq '.clip' -or $imageExts -contains $ext) {
            Add-Finding '置き場所が違うファイル' $fileRel
        }
        elseif ($Strict) {
            Add-Finding 'その他のファイル' $fileRel
        }
    }

    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory | Sort-Object Name)) {
        # 注意: PowerShell の変数名は大文字小文字を区別しないため、$Rel とは別名にする
        $childRel = if ($Rel -eq '') { $d.Name } else { "$Rel\$($d.Name)" }

        if ($d.Name -match '^(\d{8})-.+$') {
            # 作品フォルダとして検査する
            $dateText = $Matches[1]
            $name = $d.Name

            $workDate = [datetime]::MinValue
            $dateOk = [datetime]::TryParseExact($dateText, 'yyyyMMdd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$workDate)
            if (-not $dateOk) {
                Add-Finding 'フォルダ名が規則と違います' "works\$childRel"
                continue
            }

            # 完成日が未来なのは打ち間違い以外にあり得ない
            if ($workDate.Date -gt (Get-Date).Date) {
                Add-Finding '日付が未来です' "works\$childRel"
            }

            # 同名重複の検出用に記録する（報告は厳密モードのみ）
            $dupKey = $name.ToLowerInvariant()
            if (-not $workNames.ContainsKey($dupKey)) { $workNames[$dupKey] = @() }
            $workNames[$dupKey] += $childRel

            $clips = @(Get-ChildItem -LiteralPath $d.FullName -Filter *.clip -File)

            # 原本の消失（最重要）: 作品フォルダに .clip が無い
            if ($clips.Count -eq 0) {
                Add-Finding '原本が見つかりません' $childRel
            }
            else {
                # 書き出し忘れ: それぞれの .clip に「同じ名前で拡張子だけ違う画像」があるか。
                # 判定は名前の完全一致のみ（本体も差分も同じ規則）。画像の更新日時も控えておく
                $imageMap = @{}
                foreach ($img in @(Get-ChildItem -LiteralPath $d.FullName -File |
                    Where-Object { $imageExts -contains $_.Extension.ToLower() })) {
                    $imgKey = $img.BaseName.ToLowerInvariant()
                    if (-not $imageMap.ContainsKey($imgKey) -or $img.LastWriteTime -gt $imageMap[$imgKey]) {
                        $imageMap[$imgKey] = $img.LastWriteTime
                    }
                }
                foreach ($clip in $clips) {
                    # 名前が規則外の clip は「ファイル名」検査に任せ、ここでは責めない
                    if (-not $clip.BaseName.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $clipKey = $clip.BaseName.ToLowerInvariant()
                    if (-not $imageMap.ContainsKey($clipKey)) {
                        Add-Finding '書き出し忘れ' "$childRel\$($clip.Name)"
                    }
                    elseif ($Strict -and $clip.LastWriteTime -gt $imageMap[$clipKey]) {
                        # 画像より後に .clip が保存されている＝書き出し直し忘れの疑い
                        Add-Finding '書き出しが古いかもしれません' "$childRel\$($clip.Name)"
                    }
                }
            }

            # .clip の名前がフォルダ名で始まっていれば差分・改訂版として正常
            # （例: 20260801-ねこ-モザイク無し.clip / 20260801-ねこ_v2.clip）
            foreach ($clip in $clips) {
                if (-not $clip.BaseName.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-Finding 'ファイル名がフォルダ名と違います' "$childRel\$($clip.Name)"
                }
            }

            # 厳密モードのみ: 意図的かもしれないものの棚卸し
            if ($Strict) {
                # 作品フォルダの中のフォルダ（ラフ置き場・昔の名残など）
                foreach ($sub in @(Get-ChildItem -LiteralPath $d.FullName -Directory | Sort-Object Name)) {
                    Add-Finding '作品フォルダの中のフォルダ' "$childRel\$($sub.Name)\"
                }
                # .clip でも画像でもないファイル（メモ等）
                foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -File | Sort-Object Name)) {
                    $ext = $f.Extension.ToLower()
                    if ($ext -eq '.clip' -or $imageExts -contains $ext) { continue }
                    if (@('desktop.ini', 'thumbs.db') -contains $f.Name.ToLowerInvariant()) { continue }
                    Add-Finding 'その他のファイル' "$childRel\$($f.Name)"
                }
            }
        }
        else {
            $looksLikeWork = @(Get-ChildItem -LiteralPath $d.FullName -Filter *.clip -File).Count -gt 0
            if ($looksLikeWork) {
                Add-Finding 'フォルダ名が規則と違います' "works\$childRel"
            }
            elseif ($Depth -lt 6) {
                # 厳密モードのみ: 中身のないグループフォルダを棚卸しする
                if ($Strict -and @(Get-ChildItem -LiteralPath $d.FullName).Count -eq 0) {
                    Add-Finding '空のグループフォルダ' "works\$childRel"
                }
                Invoke-GenreScan -Dir $d.FullName -Rel $childRel -Depth ($Depth + 1)
            }
        }
    }
}

try {
    $ToolDir = [System.IO.Path]::GetFullPath(($ToolDir -replace '"', ''))

    # 絵の置き場を root.txt から読む
    $root = $null
    $rootFile = Join-Path $ToolDir 'root.txt'
    if (Test-Path -LiteralPath $rootFile) {
        $line = Get-Content -LiteralPath $rootFile -Encoding UTF8 -TotalCount 1
        if ($line) {
            $line = $line.Trim()
            if (Test-Path -LiteralPath $line -PathType Container) { $root = $line }
        }
    }
    if (-not $root) {
        Write-Host '先に setup.bat を実行してください。'
        return
    }

    $worksDir = Join-Path $root 'works'
    if (-not (Test-Path -LiteralPath $worksDir -PathType Container)) {
        Write-Host 'works フォルダが見つかりません。先に setup.bat を実行してください。'
        return
    }

    if ($Strict) { Write-Host '厳密点検モードで調べます。' -ForegroundColor Cyan }
    Invoke-GenreScan -Dir $worksDir -Rel '' -Depth 0

    # 厳密モードのみ: 同じ作品フォルダ名が複数の場所にあれば棚卸しする
    if ($Strict) {
        foreach ($entry in ($workNames.GetEnumerator() | Sort-Object Key)) {
            if (@($entry.Value).Count -gt 1) {
                foreach ($rel in $entry.Value) {
                    Add-Finding '同じ名前の作品が複数あります' $rel
                }
            }
        }
    }

    if ($findings.Count -eq 0) {
        Write-Host '問題は見つかりませんでした。' -ForegroundColor Green
        return
    }

    # 説明はカテゴリごとに1回だけ表示し、その下に対象を素の一覧で並べる
    Write-Host "$($findings.Count)件の問題が見つかりました。" -ForegroundColor Yellow
    $order = @(
        [pscustomobject]@{ Cat = '原本が見つかりません'
            Desc = '作品フォルダに .clip がありません。削除された可能性があります。'; Color = 'Red' }
        [pscustomobject]@{ Cat = '書き出し忘れ'
            Desc = '.clip と同じ名前の画像がありません。書き出して同じフォルダに入れてください。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '日付が未来です'
            Desc = 'フォルダ名の完成日が未来です。打ち間違いかもしれません。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = 'フォルダ名が規則と違います'
            Desc = '「YYYYMMDD-タイトル」の形に直してください。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = 'ファイル名がフォルダ名と違います'
            Desc = '名前を「フォルダ名」か「フォルダ名＋接尾辞」にしてください。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '置き場所が違うファイル'
            Desc = 'グループの階層に .clip や画像が直接置かれています。作品フォルダの中へ移してください。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '書き出しが古いかもしれません'
            Desc = '.clip が画像より後に更新されています。書き出し直しを忘れていないか確認してください。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = '作品フォルダの中のフォルダ'
            Desc = '意図して置いたものなら、そのままで構いません。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = '空のグループフォルダ'
            Desc = '中身がありません。使っていなければ消しても構いません。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = '同じ名前の作品が複数あります'
            Desc = 'コピーの置き忘れかもしれません。中身を見比べてください。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = 'その他のファイル'
            Desc = '.clip でも画像でもないファイルです。意図して置いたものなら、そのままで構いません。'; Color = 'Cyan' }
    )
    foreach ($cat in $order) {
        $items = @($findings | Where-Object { $_.Category -eq $cat.Cat })
        if ($items.Count -eq 0) { continue }
        Write-Host ''
        Write-Host "[$($cat.Cat)]" -ForegroundColor $cat.Color -NoNewline
        Write-Host " $($cat.Desc)"
        foreach ($it in $items) {
            Write-Host "  $($it.Name)"
        }
    }
}
catch {
    Write-Host ''
    Write-Host "エラーが発生しました: $($_.Exception.Message)"
}
