# atelier テストハーネス
# ダイアログを環境変数駆動の差し替えに置換した tools\*.ps1 のコピーを、
# 一時領域に組んだ偽の絵の置き場に対して実行し、結果を検分する。
#
# GRID書式（organize用）: 行ごとに ';' 区切り。各行 'タイトル|グループ'。
#   '~'=タイトル初期値のまま採用、'!'=チェックを入れない
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
# 偽の置き場は Windows の一時フォルダ（%TEMP%）の直下に作り、終了時に必ず消す。
# 途中で例外が起きても消すよう、trap で後始末する
$base = Join-Path $env:TEMP 'atelier-tests'
trap {
    Write-Output ('テストが途中で止まりました: ' + $_)
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
    Write-Output "一時フォルダを削除しました: $base"
    exit 1
}
if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
[void][System.IO.Directory]::CreateDirectory($base)

$script:fails = 0
function Assert {
    param([bool]$Cond, [string]$Name)
    if ($Cond) { Write-Output "PASS: $Name" } else { $script:fails++; Write-Output "FAIL: $Name" }
}
function New-TestFile {
    param([string]$Path, [datetime]$MTime = [datetime]'2026-01-01 12:00')
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [System.IO.File]::WriteAllText($Path, 'x')
    (Get-Item -LiteralPath $Path).LastWriteTime = $MTime
}
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# ---- 0. 構文チェック ----
foreach ($f in @('setup.ps1', 'organize.ps1', 'check.ps1')) {
    $src = [System.IO.File]::ReadAllText((Join-Path $repo "tools\$f"))
    $errs = $null
    [void][System.Management.Automation.PSParser]::Tokenize($src, [ref]$errs)
    Assert ($errs.Count -eq 0) "syntax: $f"
}

# ---- ダイアログ差し替え済みコピーの作成 ----
$toolDir = Join-Path $base 'tool'
[void][System.IO.Directory]::CreateDirectory($toolDir)

$t = [System.IO.File]::ReadAllText((Join-Path $repo 'tools\setup.ps1'))
$anchor = '$picked = [Atelier.FolderPicker]::Pick(''絵を保存するフォルダを選んでください'', $Default)'
$patch = '$picked = $env:ATELIER_TEST_PICK'
Assert ($t.Contains($anchor)) 'patch anchor: setup folder dialog'
[System.IO.File]::WriteAllText((Join-Path $toolDir 'setup.ps1'), $t.Replace($anchor, $patch), $utf8Bom)

$t = [System.IO.File]::ReadAllText((Join-Path $repo 'tools\organize.ps1'))
$anchor1 = 'if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }'
$patch1 = @'
if ($env:ATELIER_TEST_CANCEL -eq '1') { return $null }
    $specs = @($env:ATELIER_TEST_GRID -split ';')
    for ($ti = 0; $ti -lt $checkBoxes.Count -and $ti -lt $specs.Count; $ti++) {
        $parts = $specs[$ti] -split '\|'
        if ($parts[0] -eq '!') { $checkBoxes[$ti].Checked = $false }
        else {
            $checkBoxes[$ti].Checked = $true
            if ($parts[0] -ne '~') { $titleBoxes[$ti].Text = $parts[0] }
        }
        if ($parts.Count -gt 1) { $genreBoxes[$ti].Text = $parts[1] }
    }
'@
$anchor2 = '$result = [System.Windows.Forms.MessageBox]::Show($owner, $Message, ''atelier'', ''YesNo'', ''Question'')'
# 確認ダイアログの差し替え。ATELIER_TEST_RACE_FILE が指定されていれば「確認中に同名ファイルが生まれた」競合を再現する
$patch2 = 'if ($env:ATELIER_TEST_RACE_FILE) { [System.IO.File]::WriteAllText($env:ATELIER_TEST_RACE_FILE, ''RACE-ORIGINAL'') }; $result = $env:ATELIER_TEST_CONFIRM'
Assert ($t.Contains($anchor1)) 'patch anchor: organize grid dialog'
Assert ($t.Contains($anchor2)) 'patch anchor: organize confirm'
[System.IO.File]::WriteAllText((Join-Path $toolDir 'organize.ps1'), $t.Replace($anchor1, $patch1).Replace($anchor2, $patch2), $utf8Bom)

Copy-Item -LiteralPath (Join-Path $repo 'tools\check.ps1') -Destination (Join-Path $toolDir 'check.ps1')
Copy-Item -LiteralPath (Join-Path $repo 'tools\FolderPicker.cs') -Destination (Join-Path $toolDir 'FolderPicker.cs')

$setupScript = Join-Path $toolDir 'setup.ps1'
$organizeScript = Join-Path $toolDir 'organize.ps1'
$checkScript = Join-Path $toolDir 'check.ps1'
$rootDir = Join-Path $base 'root'
$wipDir = Join-Path $rootDir 'wip'

# ---- 1. setup ----
# ダイアログが実在しないパスを返した場合 → 何も書かず案内して終了
$env:ATELIER_TEST_PICK = Join-Path $base 'sonzai-shinai'
$out = (& $setupScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('見つかりませんでした')) 'setup: nonexistent dialog result rejected'
Assert (-not (Test-Path -LiteralPath (Join-Path $toolDir 'root.txt'))) 'setup: rejected pick writes no root.txt'
Assert (-not (Test-Path -LiteralPath (Join-Path $base 'sonzai-shinai'))) 'setup: rejected pick creates nothing'

# 正常系（本物のダイアログは実在フォルダしか返せない）
[void][System.IO.Directory]::CreateDirectory($rootDir)
$env:ATELIER_TEST_PICK = $rootDir
$out = (& $setupScript -ToolDir $toolDir 6>&1 | Out-String)
$rootFile = Join-Path $toolDir 'root.txt'
Assert (Test-Path -LiteralPath $rootFile) 'setup: root.txt created'
$bytes = [System.IO.File]::ReadAllBytes($rootFile)
Assert ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'setup: root.txt has BOM'
Assert ((Get-Content -LiteralPath $rootFile -Encoding UTF8 -TotalCount 1) -eq $rootDir) 'setup: root.txt content is the picked path'
Assert (Test-Path -LiteralPath $wipDir) 'setup: wip created'
Assert (Test-Path -LiteralPath (Join-Path $rootDir 'works')) 'setup: works created'
Assert ($out.Contains('準備ができました')) 'setup: success message'
$out = (& $setupScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('準備ができました')) 'setup: second run is safe'
$env:ATELIER_TEST_PICK = ''
$out = (& $setupScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('中止しました')) 'setup: cancel message'
Assert ((Get-Content -LiteralPath $rootFile -Encoding UTF8 -TotalCount 1) -eq $rootDir) 'setup: cancel keeps root.txt'

# ---- 2. organize: グループへ直接置く ----
New-TestFile (Join-Path $wipDir 'aaa.clip') ([datetime]'2026-07-03 15:00')
New-TestFile (Join-Path $wipDir 'aaa.png')
New-TestFile (Join-Path $wipDir 'aaa_thumb.png')
New-TestFile (Join-Path $wipDir 'ccc.png')
New-TestFile (Join-Path $wipDir 'bbb.clip') ([datetime]'2026-08-15 10:00')

$env:ATELIER_TEST_CANCEL = ''
$env:ATELIER_TEST_CONFIRM = 'Yes'
$env:ATELIER_TEST_GRID = '~|らくがき;~|らくがき'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
$grpDir = Join-Path $rootDir 'works\らくがき'
Assert (Test-Path -LiteralPath (Join-Path $grpDir '20260703-aaa.clip')) 'organize: clip renamed into group directly'
Assert (-not (Test-Path -LiteralPath (Join-Path $grpDir '20260703-aaa') -PathType Container)) 'organize: no per-work folder created'
Assert (Test-Path -LiteralPath (Join-Path $grpDir '20260815-bbb.clip')) 'organize: second clip into same group'
Assert (@(Get-ChildItem -LiteralPath $grpDir -Force).Count -eq 2) 'organize: group holds exactly the two clips'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'aaa.png')) 'organize: images left untouched in wip'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'aaa_thumb.png')) 'organize: suffixed image left untouched'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'ccc.png')) 'organize: unrelated image stays'
Assert ($out.Contains('2 件を移動しました')) 'organize: result count shown'
Assert ($out.Contains('[らくがき]')) 'organize: group shown in plan'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('整理するものはありません')) 'organize: nothing-to-do message'

# ---- 3. organize: 入れ子グループ・区切りの正規化 ----
New-TestFile (Join-Path $wipDir 'ddd.clip') ([datetime]'2026-08-01 09:00')
New-TestFile (Join-Path $wipDir 'ddd.png')
$env:ATELIER_TEST_GRID = '夏の絵|版権\ゆめアニメ'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $rootDir 'works\版権\ゆめアニメ\20260801-夏の絵.clip')) 'organize: nested group gets the file directly'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'ddd.png')) 'organize: image stays in wip'

New-TestFile (Join-Path $wipDir 'kkk.clip') ([datetime]'2026-08-05 09:00')
$env:ATELIER_TEST_GRID = '~|版権/その他'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $rootDir 'works\版権\その他\20260805-kkk.clip')) 'organize: slash separator normalized'

New-TestFile (Join-Path $wipDir 'mmm.clip') ([datetime]'2026-08-06 09:00')
$env:ATELIER_TEST_GRID = '~|版権＼つき'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $rootDir 'works\版権\つき\20260806-mmm.clip')) 'organize: fullwidth separator normalized'

# ---- 4. organize: スキップ各種 ----
# ① 行き先に同名の作品が既にある → その件はスキップ、既存の中身は無傷
$existing = Join-Path $rootDir 'works\版権\ゆめアニメ\20260801-夏の絵.clip'
[System.IO.File]::WriteAllText($existing, 'KEEP-ME')
New-TestFile (Join-Path $wipDir 'eee.clip') ([datetime]'2026-08-01 11:00')
$env:ATELIER_TEST_GRID = '夏の絵|版権\ゆめアニメ'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'eee.clip')) 'collision-1: same-name work stays in wip'
Assert ($out.Contains('既にあります')) 'collision-1: same-name skip message'
Assert ([System.IO.File]::ReadAllText($existing) -eq 'KEEP-ME') 'collision-1: existing file content untouched'
Remove-Item -LiteralPath (Join-Path $wipDir 'eee.clip') -Force

# ③ 確認ダイアログの間に同名ファイルが生まれた（競合）→ 上書きせず失敗として報告、元は wip に残る
New-TestFile (Join-Path $wipDir 'www.clip') ([datetime]'2026-08-09 10:00')
$raceFile = Join-Path $rootDir 'works\らくがき\20260809-www.clip'
$env:ATELIER_TEST_GRID = '~|らくがき'
$env:ATELIER_TEST_RACE_FILE = $raceFile
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
$env:ATELIER_TEST_RACE_FILE = ''
Assert ($out.Contains('移動できませんでした')) 'collision-3: race reported as move failure'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'www.clip')) 'collision-3: source stays in wip'
Assert ([System.IO.File]::ReadAllText($raceFile) -eq 'RACE-ORIGINAL') 'collision-3: file that appeared during confirm not overwritten'
Remove-Item -LiteralPath (Join-Path $wipDir 'www.clip') -Force
Remove-Item -LiteralPath $raceFile -Force

New-TestFile (Join-Path $wipDir 'fff.clip')
$env:ATELIER_TEST_GRID = 'a:b|らくがき'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'fff.clip')) 'organize: invalid-char title stays'
Assert ($out.Contains('タイトルに')) 'organize: invalid-char title message'

$env:ATELIER_TEST_GRID = '~|a?b'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('グループに')) 'organize: invalid-char group message'

$env:ATELIER_TEST_GRID = '~|\'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('グループが空')) 'organize: separator-only group message'

$env:ATELIER_TEST_GRID = '~|20260101-x'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('紛らわしい')) 'organize: date-like group rejected'

$env:ATELIER_TEST_GRID = '~'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('グループが空')) 'organize: empty group message'

$env:ATELIER_TEST_GRID = '|らくがき'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert ($out.Contains('タイトルが空')) 'organize: empty title message'

$env:ATELIER_TEST_GRID = '!'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'fff.clip')) 'organize: unchecked row stays'
Assert ($out.Contains('チェックが入っていなかった')) 'organize: all-unchecked message'

$env:ATELIER_TEST_CANCEL = '1'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'fff.clip')) 'organize: cancel keeps clip'
Assert ($out.Contains('中止しました')) 'organize: cancel message'
$env:ATELIER_TEST_CANCEL = ''
Remove-Item -LiteralPath (Join-Path $wipDir 'fff.clip') -Force

# 一部だけチェック → 残りは静かに見送り
New-TestFile (Join-Path $wipDir 'yyy.clip') ([datetime]'2026-08-04 10:00')
New-TestFile (Join-Path $wipDir 'zzz.clip') ([datetime]'2026-08-05 10:00')
$env:ATELIER_TEST_GRID = '~|らくがき;!'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $grpDir '20260804-yyy.clip')) 'organize: checked row moved'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'zzz.clip')) 'organize: unchecked row stays put'
Assert ($out.Contains('1 件はチェックを入れなかったので')) 'organize: leftover summary line'
Remove-Item -LiteralPath (Join-Path $wipDir 'zzz.clip') -Force

# 同一実行内で行き先が重複 → 後の件をスキップ
New-TestFile (Join-Path $wipDir 'iii.clip') ([datetime]'2026-08-02 10:00')
New-TestFile (Join-Path $wipDir 'jjj.clip') ([datetime]'2026-08-02 11:00')
$env:ATELIER_TEST_GRID = 'かぶり|らくがき;かぶり|らくがき'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $grpDir '20260802-かぶり.clip')) 'collision-2: first of two same-name rows moved'
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'jjj.clip')) 'collision-2: second same-name row stays in wip'
Assert ($out.Contains('もうあります')) 'collision-2: same-run duplicate message'
Remove-Item -LiteralPath (Join-Path $wipDir 'jjj.clip') -Force

# 確認で「いいえ」→ 何も変更しない
New-TestFile (Join-Path $wipDir 'hhh.clip') ([datetime]'2026-08-03 10:00')
$env:ATELIER_TEST_GRID = '~|らくがき'
$env:ATELIER_TEST_CONFIRM = 'No'
$out = (& $organizeScript -ToolDir $toolDir 6>&1 | Out-String)
Assert (Test-Path -LiteralPath (Join-Path $wipDir 'hhh.clip')) 'organize: No keeps clip in wip'
Assert (-not (Test-Path -LiteralPath (Join-Path $grpDir '20260803-hhh.clip'))) 'organize: No creates nothing'
Assert ($out.Contains('中止しました')) 'organize: No message'
Remove-Item -LiteralPath (Join-Path $wipDir 'hhh.clip') -Force
$env:ATELIER_TEST_CONFIRM = 'Yes'

# ---- 5. root.txt が無い場合 ----
$noRootTool = Join-Path $base 'tool-noroot'
[void][System.IO.Directory]::CreateDirectory($noRootTool)
Copy-Item -LiteralPath $organizeScript -Destination (Join-Path $noRootTool 'organize.ps1')
Copy-Item -LiteralPath $checkScript -Destination (Join-Path $noRootTool 'check.ps1')
$out = (& (Join-Path $noRootTool 'organize.ps1') -ToolDir $noRootTool 6>&1 | Out-String)
Assert ($out.Contains('先に setup.bat を実行してください')) 'organize: missing root.txt guidance'
$out = (& (Join-Path $noRootTool 'check.ps1') -ToolDir $noRootTool 6>&1 | Out-String)
Assert ($out.Contains('先に setup.bat を実行してください')) 'check: missing root.txt guidance'

# ---- 6. check ----
$checkTool = Join-Path $base 'tool-check'
[void][System.IO.Directory]::CreateDirectory($checkTool)
Copy-Item -LiteralPath $checkScript -Destination (Join-Path $checkTool 'check.ps1')
$checkRoot = Join-Path $base 'root-check'
[System.IO.File]::WriteAllText((Join-Path $checkTool 'root.txt'), $checkRoot, $utf8Bom)

# クリーン: 作品＝ファイルの組（差分も独立した組）
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\20260505-かこ.clip')
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\20260505-かこ.png')
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\20260505-かこ-むきし.clip')
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\20260505-かこ-むきし.jpg')
# 書き出し忘れ
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\20260815-夏の絵.clip')
# 原本消失（相方のいない画像）
New-TestFile (Join-Path $checkRoot 'works\版権\20260702-べつのやつ.png')
# 名前が規則外の clip: 名前を指摘し、かつ画像の有無も名前に関係なく見る（両方挙がる）
New-TestFile (Join-Path $checkRoot 'works\版権\なまえだけ.clip')                # 日付なし・画像なし → 名前＋書き出し忘れ
New-TestFile (Join-Path $checkRoot 'works\オリジナル\20269999-むり.clip')      # 日付が読めない・画像なし → 名前＋書き出し忘れ
New-TestFile (Join-Path $checkRoot 'works\OC\Anon\Anon.clip')                  # 日付なし・画像あり → 名前だけ
New-TestFile (Join-Path $checkRoot 'works\OC\Anon\Anon.png')
# 日付が未来
New-TestFile (Join-Path $checkRoot 'works\オリジナル\20991231-みらい.clip')
New-TestFile (Join-Path $checkRoot 'works\オリジナル\20991231-みらい.png')
# 空のグループ（厳密のみ）
[void][System.IO.Directory]::CreateDirectory((Join-Path $checkRoot 'works\そざい'))
# 同名重複（厳密のみ）
New-TestFile (Join-Path $checkRoot 'works\オリジナル\20260303-だぶり.clip')
New-TestFile (Join-Path $checkRoot 'works\オリジナル\20260303-だぶり.png')
New-TestFile (Join-Path $checkRoot 'works\版権\20260303-だぶり.clip')
New-TestFile (Join-Path $checkRoot 'works\版権\20260303-だぶり.png')
# その他のファイル（厳密のみ）と、常に無視される Windows の産物
New-TestFile (Join-Path $checkRoot 'works\よみもの.txt')
New-TestFile (Join-Path $checkRoot 'works\版権\ゆめアニメ\めも.txt')
New-TestFile (Join-Path $checkRoot 'works\desktop.ini')
[void][System.IO.Directory]::CreateDirectory((Join-Path $checkRoot 'wip'))

$out = (& (Join-Path $checkTool 'check.ps1') -ToolDir $checkTool 6>&1 | Out-String)
Assert ($out.Contains('8件の問題が見つかりました')) 'check: total count is 8'
Assert ($out.Contains('[原本が見つかりません]') -and $out.Contains('版権\20260702-べつのやつ.png')) 'check: image without clip flagged'
Assert ($out.Contains('[書き出し忘れ]') -and $out.Contains('ゆめアニメ\20260815-夏の絵.clip')) 'check: clip without image flagged'
Assert ($out.Contains('[名前が規則と違います]') -and $out.Contains('OC\Anon\Anon.clip') -and $out.Contains('版権\なまえだけ.clip') -and $out.Contains('オリジナル\20269999-むり.clip')) 'check: undated file names flagged'
$missing = ($out -split '\[')[1..99] | Where-Object { $_ -like '書き出し忘れ*' }
Assert ($missing -like '*なまえだけ.clip*' -and $missing -like '*むり.clip*') 'check: misnamed clips without image ALSO flagged as missing export'
Assert (-not ($missing -like '*Anon.clip*')) 'check: misnamed clip with its image not flagged as missing export'
Assert ($out.Contains('[日付が未来です]') -and $out.Contains('20991231-みらい.clip')) 'check: future date flagged'
Assert (-not $out.Contains('かこ')) 'check: clean file-pair works not flagged'
Assert (-not $out.Contains('だぶり')) 'check: duplicates silent in normal mode'
Assert (-not $out.Contains('めも.txt')) 'check: extra files silent in normal mode'
Assert (-not $out.Contains('desktop.ini')) 'check: windows droppings ignored'

$out = (& (Join-Path $checkTool 'check.ps1') -ToolDir $checkTool -Strict 6>&1 | Out-String)
Assert ($out.Contains('13件の問題が見つかりました')) 'check-strict: normal 8 plus 5 inventory items'
Assert ($out.Contains('[書き出し忘れ]') -and $out.Contains('[名前が規則と違います]') -and $out.Contains('[原本が見つかりません]')) 'check-strict: normal findings included'
Assert (-not $out.Contains('古いかも')) 'check-strict: no stale-export check exists'
Assert ($out.Contains('[空のグループフォルダ]') -and $out.Contains('works\そざい')) 'check-strict: empty group listed'
Assert ($out.Contains('[同じ名前の作品が複数あります]') -and $out.Contains('オリジナル\20260303-だぶり.clip') -and $out.Contains('版権\20260303-だぶり.clip')) 'check-strict: duplicate names listed'
Assert ($out.Contains('[その他のファイル]') -and $out.Contains('よみもの.txt') -and $out.Contains('ゆめアニメ\めも.txt')) 'check-strict: extra files listed'
Assert (-not $out.Contains('desktop.ini')) 'check-strict: windows droppings still ignored'
Assert ($out.Contains('厳密点検モード')) 'check-strict: mode announced'

# organize が作った実物を check にかける
$liveTool = Join-Path $base 'tool-live'
[void][System.IO.Directory]::CreateDirectory($liveTool)
Copy-Item -LiteralPath $checkScript -Destination (Join-Path $liveTool 'check.ps1')
[System.IO.File]::WriteAllText((Join-Path $liveTool 'root.txt'), $rootDir, $utf8Bom)
$out = (& (Join-Path $liveTool 'check.ps1') -ToolDir $liveTool 6>&1 | Out-String)
Assert ($out.Contains('[書き出し忘れ]') -and $out.Contains('らくがき\20260703-aaa.clip')) 'check-live: image-less works flagged'
Assert (-not $out.Contains('原本が見つかりません')) 'check-live: no false missing-original findings'
Assert (-not $out.Contains('名前が規則と違います')) 'check-live: organize output passes name rules'

# ---- 結果 ----
Write-Output ''
Write-Output "TOTAL FAILS: $script:fails"

# 結果にかかわらず、偽の置き場は必ず消す
Remove-Item -LiteralPath $base -Recurse -Force
Write-Output "一時フォルダを削除しました: $base"
exit $script:fails
