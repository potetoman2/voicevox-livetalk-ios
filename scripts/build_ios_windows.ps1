[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [string]$Ref = 'main',
    [switch]$DownloadOnly,
    [long]$RunId = 0
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCommand) { throw 'GitHub CLIが必要です。https://cli.github.com/ の公式Windows版をインストールし、gh auth login --web を実行してください。' }
& $ghCommand.Source auth status
if ($LASTEXITCODE -ne 0) { throw '先に gh auth login --web でGitHubにログインしてください。Appleのパスワードは不要です。' }

if (-not $DownloadOnly) {
    # Requires the source kit and workflow to have been uploaded to this repository.
    $started = [DateTimeOffset]::UtcNow
    & $ghCommand.Source workflow run build-ios.yml --repo $Repository --ref $Ref
    if ($LASTEXITCODE -ne 0) { throw 'クラウドビルドを開始できませんでした。リポジトリのActions画面を確認してください。' }
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Seconds 3
        $runsJson = & $ghCommand.Source run list --repo $Repository --workflow build-ios.yml --branch $Ref --event workflow_dispatch --limit 10 --json databaseId,createdAt,url
        if ($LASTEXITCODE -ne 0) { throw 'クラウドビルドの開始状況を読み取れませんでした。' }
        $candidate = @($runsJson | ConvertFrom-Json) | Where-Object { [DateTimeOffset]$_.createdAt -ge $started.AddSeconds(-2) } | Select-Object -First 1
        if ($candidate) { $RunId = $candidate.databaseId; Write-Host $candidate.url; break }
    }
    if (-not $RunId) { throw '開始した実行を特定できませんでした。ActionsでRun IDを確認し、-DownloadOnly -RunId を指定してください。' }
} elseif (-not $RunId) { throw '-DownloadOnly には -RunId が必要です。' }

Write-Host 'クラウドのMacでコンパイルしています。WindowsにXcodeをインストールする必要はありません。'
& $ghCommand.Source run watch $RunId --repo $Repository --exit-status
if ($LASTEXITCODE -ne 0) { throw 'iOSビルドが成功しませんでした。ActionsのLiveTalk-iOS-build-logを確認してください。' }
$downloadRoot = Join-Path $projectRoot ('ios-artifacts\' + $RunId)
& $ghCommand.Source run download $RunId --repo $Repository --name LiveTalk-iOS-unsigned --dir $downloadRoot
if ($LASTEXITCODE -ne 0) { throw 'IPAの取得に失敗しました。ActionsのArtifactsからダウンロードできます。' }
$ipa = Join-Path $downloadRoot 'VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa'
$checksumFile = $ipa + '.sha256'
if (-not (Test-Path -LiteralPath $ipa) -or -not (Test-Path -LiteralPath $checksumFile)) { throw 'IPAまたはチェックサムがありません。' }
$expected = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash -LiteralPath $ipa -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw 'IPAのチェックサムが一致しません。インストールしないでください。' }
Write-Host ('IPAを取得・検証しました: ' + $ipa)
Write-Host 'このIPAは署名なしです。AltStore ClassicのWindows手順で、ご自身のiPhone用に署名してインストールしてください。'
