# Copies the MMT core addons (every MMT* folder in D:\Games\MMT-src) into WoW Forever's AddOns folder.
# Runs by itself after every `git -C D:\Games\MMT-src pull` that brings changes (MMT-src's .git\hooks\post-merge);
# run it by hand for a fresh copy:  powershell -File D:\Games\MMT-modules\tools\sync_core.ps1
# Copies, not junctions: an addon updater deleting the AddOns folders then can't delete files in MMT-src.
param(
    [string]$Src = 'D:\Games\MMT-src',
    [string]$AddOns = 'D:\Games\World of Warcraft\_forever_\Interface\AddOns'
)
$failed = 0
foreach ($dir in Get-ChildItem -LiteralPath $Src -Directory -Filter 'MMT*') {
    $dst = Join-Path $AddOns $dir.Name
    $item = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    # an old junction: remove only the link, never what it points to
    if ($item -and $item.LinkType) { cmd /c rmdir "$dst" }
    robocopy $dir.FullName $dst /MIR /XD .git /NJH /NJS /NFL /NDL /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host "MMT core: copying $($dir.Name) failed ($LASTEXITCODE)"; $failed++ }
    else { Write-Host "MMT core: $($dir.Name) copied" }
}
exit $failed
