@echo off
rmdir /S /Q Cache
rmdir /S /Q Interface
rmdir /S /Q WTF

xcopy "D:\World of Warcraft\_retail_\Cache" "D:\WoWUI\Wowui\Cache" /s /e /i /h
xcopy "D:\World of Warcraft\_retail_\Interface" "D:\WoWUI\Wowui\Interface" /s /e /i /h
xcopy "D:\World of Warcraft\_retail_\WTF" "D:\WoWUI\Wowui\WTF" /s /e /i /h

:: Stage all changes (new, modified, and deleted files)
git add -A

:: Set a default commit message if none is provided
set "msg=Automated commit on %date% %time%"
if not "%~1"=="" set "msg=%~1"

:: Commit changes
git commit -m "%msg%"

:: Push to the current remote branch
git push