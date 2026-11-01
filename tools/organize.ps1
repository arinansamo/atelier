# atelier organize - wip の完成品を works\グループ\ へ移す
param([string]$ToolDir)

$ErrorActionPreference = 'Stop'

# works 配下のグループ階層を「親\子」の相対パスで列挙する。
# 作品は今やファイル（YYYYMMDD-タイトル.clip）なので、フォルダは基本すべてグループ。
# 名前が YYYYMMDD- で始まるフォルダだけは紛らわしいため候補に出さない
function Get-GenrePaths {
    param([string]$Dir, [string]$Prefix, [int]$Depth)
    $list = @()
    if ($Depth -ge 6) { return $list }
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory | Sort-Object Name)) {
        if ($d.Name -match '^\d{8}-.+$') { continue }
        $rel = if ($Prefix -eq '') { $d.Name } else { "$Prefix\$($d.Name)" }
        $list += $rel
        $list += Get-GenrePaths -Dir $d.FullName -Prefix $rel -Depth ($Depth + 1)
    }
    return $list
}

# グループ欄の文字列を段の配列に正す。\ または / 区切りで入れ子（例: 版権\グループ名）。
# IMEで入りがちな全角の＼／￥や¥も区切りとして読み替え、各段の前後の空白と末尾のドットは落とす
function Get-GenreSegments {
    param([string]$Text)
    return @(($Text -replace '[/／＼￥¥]', '\') -split '\\' |
        ForEach-Object { $_.Trim().TrimEnd('.', ' ') } | Where-Object { $_ -ne '' })
}

# 全件を1枚の表で確認・編集するダイアログ。
# 戻り値: キャンセル時は $null、OK時は各行の { Use, Title, Genre, Series } の配列（入力順）
function Show-OrganizeDialog {
    param([object[]]$Items, [string[]]$GenreList)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'atelier'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(700, 410)
    $form.Font = New-Object System.Drawing.Font('Meiryo UI', 9.5)

    $headLabel = New-Object System.Windows.Forms.Label
    $headLabel.Text = '整理するものにチェックを入れ、タイトルとグループを整えてください'
    $headLabel.Location = New-Object System.Drawing.Point(15, 12)
    $headLabel.AutoSize = $true
    $form.Controls.Add($headLabel)

    # 列見出し
    $titleHead = New-Object System.Windows.Forms.Label
    $titleHead.Text = 'タイトル'
    $titleHead.Location = New-Object System.Drawing.Point(272, 40)
    $titleHead.AutoSize = $true
    $titleHead.Font = New-Object System.Drawing.Font('Meiryo UI', 8.25)
    $titleHead.ForeColor = [System.Drawing.SystemColors]::GrayText
    $form.Controls.Add($titleHead)
    $genreHead = New-Object System.Windows.Forms.Label
    $genreHead.Text = 'グループ'
    $genreHead.Location = New-Object System.Drawing.Point(435, 40)
    $genreHead.AutoSize = $true
    $genreHead.Font = New-Object System.Drawing.Font('Meiryo UI', 8.25)
    $genreHead.ForeColor = [System.Drawing.SystemColors]::GrayText
    $form.Controls.Add($genreHead)
    $seriesHead = New-Object System.Windows.Forms.Label
    $seriesHead.Text = 'シリーズ'
    $seriesHead.Location = New-Object System.Drawing.Point(597, 40)
    $seriesHead.AutoSize = $true
    $seriesHead.Font = New-Object System.Drawing.Font('Meiryo UI', 8.25)
    $seriesHead.ForeColor = [System.Drawing.SystemColors]::GrayText
    $form.Controls.Add($seriesHead)

    # 行ごとに本物の部品を並べる。DataGridView のセル芸はイベント頼みで壊れやすいため使わない
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(15, 58)
    $panel.Size = New-Object System.Drawing.Size(670, 252)
    $panel.AutoScroll = $true
    $panel.BorderStyle = 'FixedSingle'
    $panel.BackColor = [System.Drawing.SystemColors]::Window

    $checkBoxes = @()
    $titleBoxes = @()
    $genreBoxes = @()
    $seriesBoxes = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $y = 8 + $i * 32

        # 既定はチェックなし。選んだものだけが動く（うっかりOKでの大移動を防ぐ）
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(12, ($y + 2))
        $cb.Size = New-Object System.Drawing.Size(18, 18)
        $cb.Checked = $false
        $panel.Controls.Add($cb)
        $checkBoxes += $cb

        $lb = New-Object System.Windows.Forms.Label
        $lb.Text = '{0}  ({1})' -f $Items[$i].FileName, $Items[$i].DateText
        $lb.Location = New-Object System.Drawing.Point(38, ($y + 4))
        $lb.AutoSize = $false
        $lb.Size = New-Object System.Drawing.Size(212, 18)
        $lb.AutoEllipsis = $true
        $panel.Controls.Add($lb)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(257, $y)
        $tb.Width = 152
        $tb.Text = $Items[$i].DefaultTitle
        $panel.Controls.Add($tb)
        $titleBoxes += $tb

        # 本物のコンボボックスは「一覧から選ぶ」「新しい名前を打つ」の両方が最初からできる
        $co = New-Object System.Windows.Forms.ComboBox
        $co.Location = New-Object System.Drawing.Point(417, $y)
        $co.Width = 168
        $co.DropDownStyle = 'DropDown'
        $co.DropDownWidth = 250
        if ($GenreList.Count -gt 0) { $co.Items.AddRange($GenreList) }
        $panel.Controls.Add($co)
        $genreBoxes += $co

        # シリーズ: チェックを入れると、OK のあとでグループの最後の段に完成日が付く（OK 時に読むだけ。イベントは使わない）
        $sb = New-Object System.Windows.Forms.CheckBox
        $sb.Location = New-Object System.Drawing.Point(606, ($y + 2))
        $sb.Size = New-Object System.Drawing.Size(18, 18)
        $sb.Checked = $false
        $panel.Controls.Add($sb)
        $seriesBoxes += $sb
    }
    $form.Controls.Add($panel)

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = '＼で区切るとグループの中にグループを作れます（例: 版権＼グループ名）' + [Environment]::NewLine +
        '「シリーズ」にチェックを入れると、グループの最後の段に完成日が付きます（例: うみ → 2026-10-25-うみ）'
    $hintLabel.Location = New-Object System.Drawing.Point(15, 318)
    $hintLabel.AutoSize = $false
    $hintLabel.Size = New-Object System.Drawing.Size(670, 32)
    $hintLabel.Font = New-Object System.Drawing.Font('Meiryo UI', 8.25)
    $hintLabel.ForeColor = [System.Drawing.SystemColors]::GrayText
    $form.Controls.Add($hintLabel)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(505, 365)
    $okButton.Size = New-Object System.Drawing.Size(85, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'キャンセル'
    $cancelButton.Location = New-Object System.Drawing.Point(598, 365)
    $cancelButton.Size = New-Object System.Drawing.Size(87, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

    $answers = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $answers += [pscustomobject]@{
            Use    = $checkBoxes[$i].Checked
            Title  = [string]$titleBoxes[$i].Text
            Genre  = [string]$genreBoxes[$i].Text
            Series = $seriesBoxes[$i].Checked
        }
    }
    return ,$answers
}

function Show-ConfirmDialog {
    param([string]$Message)
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $result = [System.Windows.Forms.MessageBox]::Show($owner, $Message, 'atelier', 'YesNo', 'Question')
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

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

    $wipDir = Join-Path $root 'wip'
    $worksDir = Join-Path $root 'works'
    if (-not (Test-Path -LiteralPath $wipDir -PathType Container)) {
        Write-Host 'wip フォルダが見つかりません。先に setup.bat を実行してください。'
        return
    }

    $clips = @(Get-ChildItem -LiteralPath $wipDir -Filter *.clip -File | Sort-Object Name)
    if ($clips.Count -eq 0) {
        Write-Host '整理するものはありません。'
        Write-Host 'wip フォルダに .clip が見つかりませんでした。'
        return
    }

    Write-Host "$($clips.Count) 件見つかりました。"
    $items = @()
    foreach ($clip in $clips) {
        Write-Host ('  {0}  ({1} 更新)' -f $clip.Name, $clip.LastWriteTime.ToString('yyyy-MM-dd'))
        $items += [pscustomobject]@{
            Clip         = $clip
            FileName     = $clip.Name
            DateText     = $clip.LastWriteTime.ToString('yyyy-MM-dd')
            DefaultTitle = $clip.BaseName
        }
    }

    # 既存グループ = works 配下のグループ階層
    $genres = @()
    if (Test-Path -LiteralPath $worksDir -PathType Container) {
        $genres = @(Get-GenrePaths -Dir $worksDir -Prefix '' -Depth 0)
    }

    $answers = Show-OrganizeDialog -Items $items -GenreList $genres
    if ($null -eq $answers) {
        Write-Host '中止しました。何も変更していません。'
        return
    }

    $plan = @()
    $plannedFiles = @{}
    $skipped = 0
    $left = 0

    # シリーズフォルダの日付は、同じ実行で同じシリーズに入れる行の中で一番早い完成日に揃える
    # （連作をまとめて整理したとき、行の順番で日付が変わらないように）
    $seriesDates = @{}
    for ($i = 0; $i -lt $items.Count; $i++) {
        $answer = $answers[$i]
        if (-not ($answer.Use -and $answer.Series)) { continue }
        $segs = @(Get-GenreSegments $answer.Genre)
        if ($segs.Count -eq 0 -or $segs[-1] -match '^\d{4}-\d{2}-\d{2}-.+') { continue }
        $key = ($segs -join '\').ToLowerInvariant()
        $date = $items[$i].Clip.LastWriteTime
        if (-not $seriesDates.ContainsKey($key) -or $date -lt $seriesDates[$key]) { $seriesDates[$key] = $date }
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $clip = $items[$i].Clip
        $answer = $answers[$i]

        # チェックなしは静かに見送る（既定が全行チェックなしのため、1件ずつ騒がない）
        if (-not $answer.Use) {
            $left++
            continue
        }

        # 末尾のドット・空白はフォルダ名に使えないため落とす
        $title = $answer.Title.Trim().TrimEnd('.', ' ')
        $genreSegments = @(Get-GenreSegments $answer.Genre)

        if ($title -eq '') {
            Write-Host "  スキップ: $($clip.Name)（タイトルが空です）"
            $skipped++
            continue
        }
        if ($genreSegments.Count -eq 0) {
            Write-Host "  スキップ: $($clip.Name)（グループが空です）"
            $skipped++
            continue
        }
        if ($title.IndexOfAny('\/:*?"<>|'.ToCharArray()) -ge 0) {
            Write-Host "  スキップ: $($clip.Name)（タイトルに \ / : * ? `" < > | は使えません）"
            $skipped++
            continue
        }
        if (@($genreSegments | Where-Object { $_.IndexOfAny(':*?"<>|'.ToCharArray()) -ge 0 }).Count -gt 0) {
            Write-Host "  スキップ: $($clip.Name)（グループに : * ? `" < > | は使えません）"
            $skipped++
            continue
        }
        if (@($genreSegments | Where-Object { $_ -match '^\d{8}' }).Count -gt 0) {
            Write-Host "  スキップ: $($clip.Name)（8桁の数字で始まるグループ名は作品の名前と紛らわしいため使えません）"
            $skipped++
            continue
        }

        # シリーズ: グループの最後の段に完成日を付けて「yyyy-MM-dd-名前」のシリーズフォルダにする。
        # 最後の段がすでに日付付き（一覧から既存のシリーズを選んだ）なら、そのまま使う
        if ($answer.Series -and -not ($genreSegments[-1] -match '^\d{4}-\d{2}-\d{2}-.+')) {
            $seriesName = $genreSegments[-1]
            $parentSegments = @($genreSegments | Select-Object -First ($genreSegments.Count - 1))
            $seriesDate = $seriesDates[($genreSegments -join '\').ToLowerInvariant()]
            $seriesFolder = $seriesDate.ToString('yyyy-MM-dd') + '-' + $seriesName

            # 同じ親に、同じ名前で日付だけ違うシリーズが既にあるなら、新しく作らず案内する（当て推量で合流はしない）
            $parentDir = Join-Path $root 'works'
            if ($parentSegments.Count -gt 0) { $parentDir = Join-Path $parentDir ($parentSegments -join '\') }
            $twin = $null
            if (Test-Path -LiteralPath $parentDir -PathType Container) {
                $pattern = '^\d{4}-\d{2}-\d{2}-' + [regex]::Escape($seriesName) + '$'
                $twin = @(Get-ChildItem -LiteralPath $parentDir -Directory |
                    Where-Object { $_.Name -match $pattern -and $_.Name -ne $seriesFolder } | Sort-Object Name) | Select-Object -First 1
            }
            if ($twin) {
                Write-Host "  スキップ: $($clip.Name)（同じ名前のシリーズ $($twin.Name) が既にあります。続きはグループの一覧から選んでください）"
                $skipped++
                continue
            }
            $genreSegments = $parentSegments + @($seriesFolder)
        }
        $genre = $genreSegments -join '\'

        # 作品はフォルダを挟まず、指定されたグループに「YYYYMMDD-タイトル.clip」として直接置く
        $date = $clip.LastWriteTime
        $workName = $date.ToString('yyyyMMdd') + '-' + $title
        $relDir = "works\$genre"
        $destDir = Join-Path $root $relDir
        $destFile = Join-Path $destDir "$workName.clip"

        if (Test-Path -LiteralPath $destFile) {
            Write-Host "  スキップ: $($clip.Name)（同じ名前の作品 $workName.clip が既にあります）"
            $skipped++
            continue
        }
        if ($plannedFiles.ContainsKey($destFile)) {
            Write-Host "  スキップ: $($clip.Name)（同じ日付・タイトルのものがこの中にもうあります）"
            $skipped++
            continue
        }
        $plannedFiles[$destFile] = $true

        # 動かすのは .clip だけ。画像などの他のファイルには一切触れない
        $plan += [pscustomobject]@{
            Title   = $title
            Genre   = $genre
            DestDir = $destDir
            Source  = $clip.FullName
            DestRel = "$relDir\$workName.clip"
            Dest    = $destFile
        }
    }

    if ($plan.Count -eq 0) {
        Write-Host ''
        if ($left -eq $items.Count) {
            Write-Host 'チェックが入っていなかったので、何もしませんでした。'
        } else {
            Write-Host '移動できるものがありませんでした。'
        }
        return
    }

    # 実行計画の全文はコンソールへ、確認ダイアログには要約だけを出す
    Write-Host ''
    Write-Host '以下のように移動します。'
    foreach ($item in $plan) {
        Write-Host ''
        Write-Host "  $($item.Title)  [$($item.Genre)]"
        Write-Host "    $($item.DestRel)"
    }
    Write-Host ''

    if (-not (Show-ConfirmDialog -Message "$($plan.Count)件を移動します。実行しますか?")) {
        Write-Host '中止しました。何も変更していません。'
        return
    }

    $done = 0
    $failed = 0
    foreach ($item in $plan) {
        try {
            [void][System.IO.Directory]::CreateDirectory($item.DestDir)
            [System.IO.File]::Move($item.Source, $item.Dest)
            Write-Host "  移動しました: $($item.Title)  [$($item.Genre)]"
            $done++
        }
        catch {
            # 途中で失敗しても巻き戻さない。残りの件は続行する
            Write-Host "  移動できませんでした: $($item.Title)（ファイルが開いたままになっていませんか）"
            $failed++
        }
    }

    Write-Host ''
    Write-Host "$done 件を移動しました。"
    if ($failed -gt 0) { Write-Host "$failed 件は移動できませんでした。wip に残っています。" }
    if ($skipped -gt 0) { Write-Host "$skipped 件はスキップしました。wip に残っています。" }
    if ($left -gt 0) { Write-Host "$left 件はチェックを入れなかったので、wip にそのままです。" }
}
catch {
    Write-Host ''
    Write-Host "エラーが発生しました: $($_.Exception.Message)"
}
