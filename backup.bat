@echo off
rmdir /S /Q Cache
rmdir /S /Q Interface
rmdir /S /Q WTF

xcopy "G:\World of Warcraft\_retail_\Cache" "Cache" /s /e /i /h
xcopy "G:\World of Warcraft\_retail_\Interface" "Interface" /s /e /i /h
xcopy "G:\World of Warcraft\_retail_\WTF" "WTF" /s /e /i /h

:: Stage all changes (new, modified, and deleted files)
git add -A

:: Set a default commit message if none is provided
set "msg=Automated commit on %date% %time%"
if not "%~1"=="" set "msg=%~1"

:: Commit changes
git commit -m "%msg%"

:: Push to the current remote branch
git push