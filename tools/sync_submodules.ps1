<#
.SYNOPSIS
    Sync this project's addon submodules.

.DESCRIPTION
    By default every submodule is put on its tracked branch and pulled from origin, then the
    pointers that moved are listed so they can be reviewed and committed. Nothing is pushed and,
    without -Commit, nothing is committed.

    A submodule with uncommitted changes is skipped and reported. The script never discards work.

.PARAMETER Pinned
    The other direction: put every submodule back on the commit this repository has recorded,
    throwing away any drift in the checkout. Where the recorded commit is the tip of the tracked
    branch the submodule ends up on that branch; otherwise git leaves it detached, which is what
    a recorded pointer behind the branch tip means.

.PARAMETER Commit
    After a default run, stage and commit the pointers that moved. Does not push.

.EXAMPLE
    tools\sync_submodules.ps1
    Bring every submodule up to date and list what moved.

.EXAMPLE
    tools\sync_submodules.ps1 -Commit
    The same, and commit the bumped pointers.

.EXAMPLE
    tools\sync_submodules.ps1 -Pinned
    Put every submodule back on the commit this repository records.
#>
[CmdletBinding()]
param(
    [switch]$Pinned,
    [switch]$Commit
)

$ErrorActionPreference = "Stop"

if ($Pinned -and $Commit) {
    Write-Error "-Commit applies to the default direction only; -Pinned moves submodules back to what is already recorded."
    exit 1
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path (Join-Path $root ".gitmodules"))) {
    Write-Error "No .gitmodules in $root."
    exit 1
}

# "submodule.addons/gta.path addons/gta" -> "addons/gta"
$paths = git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
    ForEach-Object { ($_ -split ' ', 2)[1] }

Write-Host "Repository: $root"
Write-Host "Submodules: $($paths.Count)"
Write-Host ""

# A fresh clone leaves the submodule directories empty. Fill in only those, rather than running a
# blanket update, which would reset a checkout that is deliberately sitting somewhere else.
foreach ($path in $paths) {
    if (-not (Test-Path (Join-Path $path ".git"))) {
        Write-Host ("{0,-34} not checked out, initialising" -f (Split-Path $path -Leaf))
        git submodule update --init --recursive --quiet -- $path
    }
}

$moved = [System.Collections.Generic.List[object]]::new()
$skipped = [System.Collections.Generic.List[object]]::new()

foreach ($path in $paths) {
    $name = Split-Path $path -Leaf
    $before = (git -C $path rev-parse HEAD).Trim()

    # --ignore-submodules=all so the guard fires on real file edits only. An addon's own nested
    # submodules (a demo's addons/controls) drift as a matter of course and are not work to protect.
    $dirty = git -C $path status --porcelain --ignore-submodules=all
    if ($dirty) {
        $skipped.Add([pscustomobject]@{ Path = $path; Reason = "$(($dirty | Measure-Object).Count) uncommitted change(s)" })
        Write-Host ("{0,-34} skipped, uncommitted changes" -f $name) -ForegroundColor Yellow
        continue
    }

    if ($Pinned) {
        # --checkout forces the recorded commit even if the submodule sits on a branch.
        git submodule update --init --checkout --force --quiet -- $path
    }
    else {
        # An explicit branch in .gitmodules wins; otherwise follow the remote's default branch.
        $branch = git config -f .gitmodules --get "submodule.$path.branch"
        if (-not $branch) {
            $head = git -C $path symbolic-ref --short refs/remotes/origin/HEAD 2>$null
            $branch = if ($head) { ($head -replace '^origin/', '').Trim() } else { "main" }
        }

        git -C $path fetch origin $branch --quiet
        git -C $path checkout $branch --quiet
        # --ff-only so a submodule that has local commits stops the run instead of merging.
        git -C $path merge --ff-only "origin/$branch" --quiet
    }

    # Bring the addon's own nested submodules (a demo's addons/controls) onto the commits the addon
    # records, so the checkout is consistent all the way down rather than showing permanent drift.
    git -C $path submodule update --init --recursive --quiet

    $after = (git -C $path rev-parse HEAD).Trim()

    if ($before -eq $after) {
        Write-Host ("{0,-34} {1}  unchanged" -f $name, $after.Substring(0, 7)) -ForegroundColor DarkGray
        continue
    }

    $range = if ($Pinned) { "$after..$before" } else { "$before..$after" }
    $count = (git -C $path rev-list --count $range).Trim()
    $word = if ($Pinned) { "back" } else { "ahead" }

    $moved.Add([pscustomobject]@{ Path = $path; Before = $before; After = $after; Count = $count })
    Write-Host ("{0,-34} {1} -> {2}  ({3} commits {4})" -f $name, $before.Substring(0, 7), $after.Substring(0, 7), $count, $word) -ForegroundColor Green
}

Write-Host ""

if ($skipped.Count -gt 0) {
    Write-Host "Skipped, sync them by hand once the work in them is committed or stashed:" -ForegroundColor Yellow
    foreach ($s in $skipped) { Write-Host "  $($s.Path)  $($s.Reason)" }
    Write-Host ""
}

if ($moved.Count -eq 0) {
    Write-Host "Every submodule already matches. Nothing to commit."
    exit 0
}

if ($Pinned) {
    Write-Host "$($moved.Count) submodule(s) restored to the recorded pointers. The working tree is clean by definition."
    exit 0
}

$changed = @($moved | ForEach-Object { $_.Path })

if ($Commit) {
    git add -- $changed
    $body = ($moved | ForEach-Object { "- $($_.Path): $($_.Before.Substring(0,7)) -> $($_.After.Substring(0,7)) ($($_.Count) commits)" }) -join "`n"
    git commit -m "Bump the addon submodules" -m $body
    Write-Host ""
    Write-Host "Committed. Push when ready: git push origin $(git branch --show-current)"
}
else {
    Write-Host "$($moved.Count) pointer(s) moved. Review, then:"
    Write-Host "  git add $($changed -join ' ')"
    Write-Host "  git commit -m ""Bump the addon submodules"""
}
