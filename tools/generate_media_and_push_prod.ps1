param(
    [string]$Remote = "origin",
    [string]$Branch = "prod",
    [string]$CommitMessage = "chore: add generated media"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Name"
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot

try {
    Invoke-Step -Name "Convert OGG to MP3" -Action {
        python tools/convert_ogg_to_mp3.py --skip-existing
    }

    Invoke-Step -Name "Build MP4 videos" -Action {
        python tools/build_song_videos.py --skip-existing --use-ogg-if-mp3-missing
    }

    Invoke-Step -Name "Build song manifest" -Action {
        python tools/build_song_manifest.py
    }

    Invoke-Step -Name "Build preparsed chart chunks" -Action {
        python tools/build_song_charts.py
    }

    Invoke-Step -Name "Stage game-data" -Action {
        git add -A game-data
    }

    Invoke-Step -Name "Stage generated media" -Action {
        git add -f "songs/**/*.mp3" "songs/**/*.mp4"
    }

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "No staged changes detected. Nothing to commit." -ForegroundColor Yellow
        exit 0
    }

    Invoke-Step -Name "Commit generated files" -Action {
        git commit -m $CommitMessage
    }

    $currentBranch = ""
    $rawBranch = git branch --show-current
    if ($LASTEXITCODE -eq 0) {
        $currentBranch = $rawBranch.Trim()
    }

    Invoke-Step -Name "Push to $Remote/$Branch" -Action {
        if ($currentBranch -eq $Branch) {
            git push $Remote $Branch
        }
        else {
            Write-Host "Pushing current HEAD to $Remote/$Branch (local branch: $currentBranch)" -ForegroundColor Yellow
            git push $Remote ("HEAD:" + $Branch)
        }
    }
}
finally {
    Pop-Location
}
