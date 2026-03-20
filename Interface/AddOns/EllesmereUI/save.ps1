# Commits and pushes your current changes to GitHub (no release)
param([string]$msg = "Save progress")
Set-Location "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\EllesmereUI"
git add -A
git commit -m $msg
git push
Write-Host "Saved: $msg"
