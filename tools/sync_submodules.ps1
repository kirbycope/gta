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

.PARAMETER Push
    The outgoing direction, for work edited here rather than in the addon's own checkout. Every
    submodule holding uncommitted file changes is committed with -Message and pushed to its own
    repository, along with any commits it already had waiting. The bumped pointers are then staged
    here, ready for one commit of your own. This repository is never committed or pushed for you.

.PARAMETER Message
    The commit message used in each submodule that -Push commits. Required with -Push.

.PARAMETER DryRun
    With -Push, print what would be committed and pushed without doing any of it.

.EXAMPLE
    tools\sync_submodules.ps1
    Bring every submodule up to date and list what moved.

.EXAMPLE
    tools\sync_submodules.ps1 -Commit
    The same, and commit the bumped pointers.

.EXAMPLE
    tools\sync_submodules.ps1 -Pinned
    Put every submodule back on the commit this repository records.

.EXAMPLE
    tools\sync_submodules.ps1 -Push -Message "fix the swim ledge ray"
    Commit and push every addon edited here, then stage the new pointers.
#>
[CmdletBinding()]
param(
    [switch]$Pinned,
    [switch]$Commit,
    [switch]$Push,
    [string]$Message,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($Pinned -and $Commit) {
    Write-Error "-Commit applies to the default direction only; -Pinned moves submodules back to what is already recorded."
    exit 1
}

if ($Push -and ($Pinned -or $Commit)) {
    Write-Error "-Push is its own direction; do not combine it with -Pinned or -Commit."
    exit 1
}

if ($Push -and -not $Message) {
    Write-Error "-Push needs -Message ""...""; it is the commit message used in each submodule."
    exit 1
}

if ($DryRun -and -not $Push) {
    Write-Error "-DryRun applies to -Push only."
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

if ($Push) {
    $pushed = [System.Collections.Generic.List[object]]::new()
    $blocked = [System.Collections.Generic.List[object]]::new()

    foreach ($path in $paths) {
        $name = Split-Path $path -Leaf
        $branch = git -C $path branch --show-current

        $dirty = git -C $path status --porcelain --ignore-submodules=all
        $ahead = if ($branch) { [int](git -C $path rev-list --count "origin/$branch..HEAD") } else { 0 }

        if (-not $dirty -and $ahead -eq 0) {
            Write-Host ("{0,-34} nothing to push" -f $name) -ForegroundColor DarkGray
            continue
        }

        # A detached checkout has no branch to push to. The pull direction puts one back.
        if (-not $branch) {
            $blocked.Add([pscustomobject]@{ Name = $name; Reason = "detached HEAD, run the script with no flags first" })
            Write-Host ("{0,-34} detached, cannot push" -f $name) -ForegroundColor Red
            continue
        }

        $fileCount = ($dirty | Measure-Object).Count

        if ($DryRun) {
            $what = @()
            if ($fileCount -gt 0) { $what += "commit $fileCount file(s)" }
            if ($ahead -gt 0) { $what += "push $ahead existing commit(s)" }
            Write-Host ("{0,-34} would {1}" -f $name, ($what -join ", ")) -ForegroundColor Cyan
            $dirty | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkCyan }
            continue
        }

        if ($fileCount -gt 0) {
            git -C $path add -A
            git -C $path commit -q -m $Message
        }

        git -C $path push origin $branch --quiet
        $head = (git -C $path rev-parse --short HEAD).Trim()

        $pushed.Add([pscustomobject]@{ Path = $path; Name = $name; Head = $head })
        Write-Host ("{0,-34} {1} pushed to {2}" -f $name, $head, $branch) -ForegroundColor Green
    }

    Write-Host ""

    if ($blocked.Count -gt 0) {
        Write-Host "Could not push:" -ForegroundColor Red
        foreach ($b in $blocked) { Write-Host "  $($b.Name)  $($b.Reason)" }
        Write-Host ""
    }

    if ($DryRun) {
        Write-Host "Dry run, nothing was committed or pushed."
        exit 0
    }

    if ($pushed.Count -eq 0) {
        Write-Host "No submodule had anything to push."
        exit 0
    }

    # Stage the new pointers, but leave the commit here to the caller: this repository's history is
    # theirs to write, and the addon change usually lands beside project changes in one commit.
    $changed = @($pushed | ForEach-Object { $_.Path })
    git add -- $changed

    Write-Host "$($pushed.Count) addon(s) pushed. Their new pointers are staged here:"
    foreach ($p in $pushed) { Write-Host "  $($p.Path)  -> $($p.Head)" }
    Write-Host ""
    Write-Host "Commit and push this repository when ready:"
    Write-Host "  git commit -m ""..."" ; git push origin $(git branch --show-current)"
    exit 0
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
