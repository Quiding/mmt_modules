# Copies addon folders from a git clone into WoW Forever's AddOns folder.
# By default the MMT core addons (every MMT* folder in D:\Games\MMT-src); with -Src / -Filter any other
# repo, e.g. HUF:  powershell -File D:\Games\MMT-modules\tools\sync_core.ps1 -Src D:\Games\HUF-src -Filter 'HUF*'
# Runs by itself after every `git -C <repo> pull` that brings changes (each clone's .git\hooks\post-merge:
# D:\Games\MMT-src and D:\Games\HUF-src); run it by hand for a fresh copy.
# Copies, not junctions: an addon updater deleting the AddOns folders then can't delete files in the clone.
param(
    [string]$Src = 'D:\Games\MMT-src',
    [string]$AddOns = 'D:\Games\World of Warcraft\_forever_\Interface\AddOns',
    [string]$Filter = 'MMT*'
)
$failed = 0
foreach ($dir in Get-ChildItem -LiteralPath $Src -Directory -Filter $Filter) {
    $dst = Join-Path $AddOns $dir.Name
    $item = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    # an old junction: remove only the link, never what it points to
    if ($item -and $item.LinkType) { cmd /c rmdir "$dst" }
    robocopy $dir.FullName $dst /MIR /XD .git /NJH /NJS /NFL /NDL /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host "Copying $($dir.Name) failed ($LASTEXITCODE)"; $failed++ }
    else { Write-Host "$($dir.Name) copied" }
}
exit $failed
