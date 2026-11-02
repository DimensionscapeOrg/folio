# Packs a haxelib release of folio: bin/folio-<version>.zip, holding exactly the files git
# tracks at HEAD, so nothing built or local rides along. It refuses a tree with uncommitted
# changes, since the zip would not match what is committed.
#
#   powershell -File build/release.ps1           packs the zip
#   powershell -File build/release.ps1 -Submit   packs it, then runs haxelib submit
param([switch]$Submit)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (git status --porcelain) {
    throw 'Uncommitted changes: commit them first, so the release is what the repository holds.'
}
$version = (Get-Content haxelib.json -Raw | ConvertFrom-Json).version
New-Item -ItemType Directory -Force bin | Out-Null
$zip = "bin/folio-$version.zip"
git archive --format=zip -o $zip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
"packed $zip ($((Get-Item $zip).Length) bytes) from $(git rev-parse --short HEAD), version $version"

if ($Submit) {
    haxelib submit $zip
    if ($LASTEXITCODE -ne 0) { throw 'haxelib submit failed' }
} else {
    "to publish: haxelib submit $zip"
}
