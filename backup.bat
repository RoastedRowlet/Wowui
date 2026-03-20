@echo off
cd /d D:\World of Warcraft\_retail_
:: Stage all changes (new, modified, and deleted files)
git add -A

:: Set a default commit message if none is provided
set "msg=Automated commit on %date% %time%"
if not "%~1"=="" set "msg=%~1"

:: Commit changes
git commit -m "%msg%"

:: Push to the current remote branch
git push
pause