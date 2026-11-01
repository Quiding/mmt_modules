# Links every MMT_* module folder of this repo into the game's AddOns folder as an NTFS junction,
# so the game always runs what's in the repo (no copying). Safe to run any time:
#  - a junction that's already right is left alone,
#  - a junction pointing elsewhere is replaced (removing a junction never touches its files),
#  - a REAL folder in the way is moved to D:\Games\MMT-modules-old-copy\<date>, never deleted.
#
#   powershell -ExecutionPolicy Bypass -File D:\Games\MMT-modules\tools\link_addons.ps1
#   ... -AddOns "<another AddOns folder>"
param([string]$AddOns = "D:\Games\World of Warcraft\_forever_\Interface\AddOns")

$repo = Split-Path -Parent $PSScriptRoot
$backup = Join-Path "D:\Games\MMT-modules-old-copy" (Get-Date -Format "yyyy-MM-dd_HHmm")

Get-ChildItem $repo -Directory | Where-Object { $_.Name -like "MMT_*" } | ForEach-Object {
    $name = $_.Name
    $link = Join-Path $AddOns $name
    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq "Junction") {
        if (@($item.Target)[0] -eq $_.FullName) { "ok       $name"; return }
        # a junction elsewhere: remove the LINK only (Delete on the DirectoryInfo, never Remove-Item -Recurse)
        $item.Delete()
        "relinked $name (was -> $(@($item.Target)[0]))"
    } elseif ($item) {
        New-Item -ItemType Directory -Force $backup | Out-Null
        Move-Item $link (Join-Path $backup $name)
        "moved    $name (a real folder) to $backup"
    }
    New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
    if (-not $item -or $item.LinkType -ne "Junction" -or @($item.Target)[0] -ne $_.FullName) { "linked   $name" }
}
