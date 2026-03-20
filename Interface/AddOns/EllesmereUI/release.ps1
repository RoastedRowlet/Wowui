# Commits, tags, and pushes a release to trigger the BigWigs packager
param([Parameter(Mandatory)][string]$version)
Set-Location "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\EllesmereUI"
git add -A
git commit -m "Release v$version"
git tag "v$version"
git push
git push --tags
Write-Host "Released v$version - check GitHub Actions for packaging status"
