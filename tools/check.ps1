# atelier check - 構成の異常を検出して報告する（自動修正はしない）
# -Strict を付けると、意図的かもしれない細かい点まで一覧する（check-strict.bat から使う）
param([string]$ToolDir, [switch]$Strict)

$ErrorActionPreference = 'Stop'

$findings = New-Object 'System.Collections.Generic.List[object]'
$imageExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.psd', '.tif', '.tiff')
$ignoreNames = @('desktop.ini', 'thumbs.db')
$workNames = @{}

function Add-Finding {
    param([string]$Category, [string]$Name)
    $findings.Add([pscustomobject]@{ Category = $Category; Name = $Name })
}

# works 配下を再帰的に歩く。フォルダはすべてグループ。
# 作品は「YYYYMMDD-タイトル」の名前を持つ .clip ファイルと、その同名画像のひと組
function Invoke-GroupScan {
    param([string]$Dir, [string]$Rel, [int]$Depth)

    $files = @(Get-ChildItem -LiteralPath $Dir -File | Sort-Object Name)
    $clips = @($files | Where-Object { $_.Extension.ToLower() -eq '.clip' })
    $images = @($files | Where-Object { $imageExts -contains $_.Extension.ToLower() })

    # 同じ場所にある画像の名前
    $imageNames = @{}
    foreach ($img in $images) { $imageNames[$img.BaseName.ToLowerInvariant()] = $true }
    $clipNames = @{}
    foreach ($clip in $clips) { $clipNames[$clip.BaseName.ToLowerInvariant()] = $true }

    foreach ($clip in $clips) {
        $relName = if ($Rel -eq '') { $clip.Name } else { "$Rel\$($clip.Name)" }

        # 名前が YYYYMMDD- で始まるかは行儀の問題。画像の有無とは独立に扱う
        $workDate = [datetime]::MinValue
        $nameOk = ($clip.BaseName -match '^(\d{8})-.+') -and
            [datetime]::TryParseExact($Matches[1], 'yyyyMMdd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$workDate)
        if (-not $nameOk) {
            Add-Finding '名前が規則と違います' $relName
        }
        elseif ($workDate.Date -gt (Get-Date).Date) {
            # 完成日が未来なのは打ち間違い以外にあり得ない
            Add-Finding '日付が未来です' $relName
        }

        # 同名重複の検出用に記録する（報告は厳密モードのみ）
        $dupKey = $clip.BaseName.ToLowerInvariant()
        if (-not $workNames.ContainsKey($dupKey)) { $workNames[$dupKey] = @() }
        $workNames[$dupKey] += $relName

        # 書き出し忘れ: 同じ場所に「同じ名前で拡張子だけ違う画像」があるか（完全一致のみ）。
        # 名前の行儀に関係なく、すべての .clip に適用する
        if (-not $imageNames.ContainsKey($clip.BaseName.ToLowerInvariant())) {
            Add-Finding '書き出し忘れ' $relName
        }
    }

    # 原本の消失（最重要）: 同じ名前の .clip がいない画像
    foreach ($img in $images) {
        if (-not $clipNames.ContainsKey($img.BaseName.ToLowerInvariant())) {
            $relName = if ($Rel -eq '') { $img.Name } else { "$Rel\$($img.Name)" }
            Add-Finding '原本が見つかりません' $relName
        }
    }

    # 厳密モードのみ: .clip でも画像でもないファイルの棚卸し（メモ等、意図的な置き物のこともある）
    if ($Strict) {
        foreach ($f in $files) {
            $ext = $f.Extension.ToLower()
            if ($ext -eq '.clip' -or $imageExts -contains $ext) { continue }
            if ($ignoreNames -contains $f.Name.ToLowerInvariant()) { continue }
            $relName = if ($Rel -eq '') { $f.Name } else { "$Rel\$($f.Name)" }
            Add-Finding 'その他のファイル' $relName
        }
    }

    # サブフォルダはすべてグループとして潜る
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory | Sort-Object Name)) {
        $childRel = if ($Rel -eq '') { $d.Name } else { "$Rel\$($d.Name)" }
        if ($Depth -lt 6) {
            # 厳密モードのみ: 中身のないグループフォルダを棚卸しする
            if ($Strict -and @(Get-ChildItem -LiteralPath $d.FullName).Count -eq 0) {
                Add-Finding '空のグループフォルダ' "works\$childRel"
            }
            Invoke-GroupScan -Dir $d.FullName -Rel $childRel -Depth ($Depth + 1)
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
    Invoke-GroupScan -Dir $worksDir -Rel '' -Depth 0

    # 厳密モードのみ: 同じ名前の作品が複数の場所にあれば棚卸しする
    if ($Strict) {
        foreach ($entry in ($workNames.GetEnumerator() | Sort-Object Key)) {
            if (@($entry.Value).Count -gt 1) {
                foreach ($rel in $entry.Value) {
                    Add-Finding '同じ名前の作品が複数あります' $rel
                }
            }
        }
    }

    # 通常モードは「直すべきもの」を出す。厳密モードはそれに加えて「参考情報」も出す
    $order = @(
        [pscustomobject]@{ Cat = '原本が見つかりません'; Strict = $false
            Desc = '画像はあるのに、同じ名前の .clip がありません。原本が消えた可能性があります。'; Color = 'Red' }
        [pscustomobject]@{ Cat = '書き出し忘れ'; Strict = $false
            Desc = '.clip と同じ名前の画像がありません。書き出して同じ場所に入れてください。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '日付が未来です'; Strict = $false
            Desc = '名前の完成日が未来です。打ち間違いかもしれません。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '名前が規則と違います'; Strict = $false
            Desc = 'この .clip のファイル名を「YYYYMMDD-タイトル」で始まる形にしてください（フォルダ名は自由です）。'; Color = 'Yellow' }
        [pscustomobject]@{ Cat = '空のグループフォルダ'; Strict = $true
            Desc = '中身がありません。使っていなければ消しても構いません。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = '同じ名前の作品が複数あります'; Strict = $true
            Desc = 'コピーの置き忘れかもしれません。中身を見比べてください。'; Color = 'Cyan' }
        [pscustomobject]@{ Cat = 'その他のファイル'; Strict = $true
            Desc = '.clip でも画像でもないファイルです。意図して置いたものなら、そのままで構いません。'; Color = 'Cyan' }
    )
    $shown = @($order | Where-Object { (-not $_.Strict) -or $Strict })
    $visible = @($findings | Where-Object { $cat = $_.Category; @($shown | Where-Object { $_.Cat -eq $cat }).Count -gt 0 })

    if ($visible.Count -eq 0) {
        Write-Host '問題は見つかりませんでした。' -ForegroundColor Green
        return
    }

    # 説明はカテゴリごとに1回だけ表示し、その下に対象を素の一覧で並べる
    Write-Host "$($visible.Count)件の問題が見つかりました。" -ForegroundColor Yellow
    foreach ($cat in $shown) {
        $items = @($visible | Where-Object { $_.Category -eq $cat.Cat })
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
