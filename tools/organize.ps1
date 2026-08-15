# atelier organize - wip の完成品を works\グループ\ へ移す
param([string]$ToolDir)

$ErrorActionPreference = 'Stop'

# works 配下のグループ階層を「親\子」の相対パスで列挙する。
# 作品フォルダ（YYYYMMDD- で始まる、または .clip を直接持つもの）は除外する
function Get-GenrePaths {
    param([string]$Dir, [string]$Prefix, [int]$Depth)
    $list = @()
    if ($Depth -ge 6) { return $list }
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory | Sort-Object Name)) {
        if ($d.Name -match '^\d{8}-.+$') { continue }
        if (@(Get-ChildItem -LiteralPath $d.FullName -Filter *.clip -File).Count -gt 0) { continue }
        $rel = if ($Prefix -eq '') { $d.Name } else { "$Prefix\$($d.Name)" }
        $list += $rel
        $list += Get-GenrePaths -Dir $d.FullName -Prefix $rel -Depth ($Depth + 1)
    }
    return $list
}

# 全件を1枚の表で確認・編集するダイアログ。
# 戻り値: キャンセル時は $null、OK時は各行の { Use, Title, Genre } の配列（入力順）
function Show-OrganizeDialog {
    param([object[]]$Items, [string[]]$GenreList)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'atelier'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(640, 395)
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

    # 行ごとに本物の部品を並べる。DataGridView のセル芸はイベント頼みで壊れやすいため使わない
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(15, 58)
    $panel.Size = New-Object System.Drawing.Size(610, 252)
    $panel.AutoScroll = $true
    $panel.BorderStyle = 'FixedSingle'
    $panel.BackColor = [System.Drawing.SystemColors]::Window

    $checkBoxes = @()
    $titleBoxes = @()
    $genreBoxes = @()
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
    }
    $form.Controls.Add($panel)

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = '＼で区切るとグループの中にグループを作れます（例: 版権＼グループ名）'
    $hintLabel.Location = New-Object System.Drawing.Point(15, 320)
    $hintLabel.AutoSize = $false
    $hintLabel.Size = New-Object System.Drawing.Size(610, 18)
    $hintLabel.Font = New-Object System.Drawing.Font('Meiryo UI', 8.25)
    $hintLabel.ForeColor = [System.Drawing.SystemColors]::GrayText
    $form.Controls.Add($hintLabel)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(445, 350)
    $okButton.Size = New-Object System.Drawing.Size(85, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'キャンセル'
    $cancelButton.Location = New-Object System.Drawing.Point(538, 350)
    $cancelButton.Size = New-Object System.Drawing.Size(87, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

    $answers = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $answers += [pscustomobject]@{
            Use   = $checkBoxes[$i].Checked
            Title = [string]$titleBoxes[$i].Text
            Genre = [string]$genreBoxes[$i].Text
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
    $plannedDirs = @{}
    $skipped = 0
    $left = 0

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
        # グループは \ または / 区切りで入れ子にできる（例: 版権\グループ名）
        # IMEで入りがちな全角の＼／￥や¥も区切りとして読み替える
        $genreSegments = @(($answer.Genre -replace '[/／＼￥¥]', '\') -split '\\' |
            ForEach-Object { $_.Trim().TrimEnd('.', ' ') } | Where-Object { $_ -ne '' })

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
            Write-Host "  スキップ: $($clip.Name)（8桁の数字で始まるグループ名は作品フォルダと紛らわしいため使えません）"
            $skipped++
            continue
        }
        $genre = $genreSegments -join '\'

        # 行き先の途中に .clip を直接持つフォルダ（＝作品フォルダ）があれば、その中には作らない
        $probe = $worksDir
        $hitWork = $null
        foreach ($seg in $genreSegments) {
            $probe = Join-Path $probe $seg
            if (-not (Test-Path -LiteralPath $probe -PathType Container)) { break }
            if (@(Get-ChildItem -LiteralPath $probe -Filter *.clip -File).Count -gt 0) { $hitWork = $seg; break }
        }
        if ($hitWork) {
            Write-Host "  スキップ: $($clip.Name)（「$hitWork」は作品フォルダです。その中には整理できません）"
            $skipped++
            continue
        }

        $date = $clip.LastWriteTime
        $folderName = $date.ToString('yyyyMMdd') + '-' + $title
        $relDir = 'works\{0}\{1}' -f $genre, $folderName
        $destDir = Join-Path $root $relDir

        if (Test-Path -LiteralPath $destDir) {
            Write-Host "  スキップ: $($clip.Name)（移動先の $folderName フォルダが既にあります）"
            $skipped++
            continue
        }
        if ($plannedDirs.ContainsKey($destDir)) {
            Write-Host "  スキップ: $($clip.Name)（同じ日付・タイトルのものがこの中にもうあります）"
            $skipped++
            continue
        }
        $plannedDirs[$destDir] = $true

        # 動かすのは .clip だけ。画像などの他のファイルには一切触れない
        $plan += [pscustomobject]@{
            Title   = $title
            Genre   = $genre
            DestDir = $destDir
            Source  = $clip.FullName
            DestRel = "$relDir\$folderName.clip"
            Dest    = Join-Path $destDir "$folderName.clip"
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
