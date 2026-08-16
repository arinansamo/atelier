# atelier setup - 絵の置き場を決めて、フォルダを用意する
param([string]$ToolDir)

$ErrorActionPreference = 'Stop'

function Show-FolderDialog {
    param([string]$Default)
    $picked = [Atelier.FolderPicker]::Pick('絵を保存するフォルダを選んでください', $Default)
    return $picked
}

try {
    # フォルダ選択の下回り（新方式 IFileDialog の COM 呼び出し）は FolderPicker.cs を参照。
    # 実行時にその場でコンパイルされるため、追加インストールは不要
    if (-not ('Atelier.FolderPicker' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'FolderPicker.cs')
    }

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

    # ダイアログの返り値でも無検証では信じない。実在しないパスならここで止める
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Host '選ばれたフォルダが見つかりませんでした。'
        Write-Host 'もう一度 setup.bat を実行して、選び直してください。'
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
