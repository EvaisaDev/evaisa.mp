@echo off
REM Define the gitzip function
:gitzip
REM Extract the full directory name, including dots
for %%I in ("%CD%") do set dirname=%%~nxI

REM Create the archive while respecting .gitignore
git archive --format=zip --output="%dirname%.zip" HEAD
goto :eof

REM Change directory to "mydir"
cd mydir

REM Call the gitzip function
call :gitzip
