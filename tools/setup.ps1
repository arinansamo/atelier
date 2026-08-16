# atelier setup - 絵の置き場を決めて、フォルダを用意する
param([string]$ToolDir)

$ErrorActionPreference = 'Stop'

function Show-FolderDialog {
    param([string]$Default)
    # オーナーを最前面にしておかないと、ダイアログがコンソールの裏に隠れることがある
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = '絵を保存するフォルダを選んでください'
    $dialog.SelectedPath = $Default
    if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

try {
    Add-Type -AssemblyName System.Windows.Forms

    # バッチから渡されるパスを正規化する（末尾の \. や、引用符の混入を除く）
    $ToolDir = [System.IO.Path]::GetFullPath(($ToolDir -replace '"', ''))
    $rootFile = Join-Path $ToolDir 'root.txt'

    # 既定値は前回選んだ場所。初回はツール自身の場所
    $defaultPath = $ToolDir
    if (Test-Path -LiteralPath $rootFile) {
        $saved = Get-Content -LiteralPath $rootFile -Encoding UTF8 -TotalCount 1
        if ($saved) {
            $saved = $saved.Trim()
            if (Test-Path -LiteralPath $saved -PathType Container) { $defaultPath = $saved }
        }
    }

    $root = Show-FolderDialog -Default $defaultPath
    if (-not $root) {
        Write-Host '中止しました。設定は変更していません。'
        return
    }

    # フォルダ選択ダイアログは「新しいフォルダーの作成」→改名→即OK の操作で、
    # 改名前の古いパスを返すことがある（Windows 側の既知の癖）。
    # 存在しないパスを黙って作り直すと選んだつもりの場所とずれるため、ここで止める
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Host '選ばれたフォルダが見つかりませんでした。'
        Write-Host '（フォルダを作って名前を変えた直後に起きることがあります）'
        Write-Host 'もう一度 setup.bat を実行して、先ほど作ったフォルダを選び直してください。'
        return
    }

    # root.txt に書く（パスに日本語が含まれても化けないよう UTF-8 BOM付き）
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($rootFile, $root, $utf8Bom)

    # 置き場のフォルダを用意する（既にあれば何もしない）
    foreach ($sub in @('wip', 'works')) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $root $sub))
    }

    Write-Host ''
    Write-Host '準備ができました。'
    Write-Host ''
    Write-Host "  絵の置き場: $root"
    Write-Host ''
    Write-Host '  1. クリスタで絵を描いたら、wip フォルダに保存してください'
    Write-Host '  2. 完成したら「organize.bat」をダブルクリックしてください'
}
catch {
    Write-Host ''
    Write-Host "エラーが発生しました: $($_.Exception.Message)"
}
