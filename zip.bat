@echo off
REM Define the gitzip function
:gitzip

REM -- Extract the folder name of the directory containing this batch script --
REM    (%~dp0 is the full path of the folder where the batch is located; 
REM    the trailing dot (.) ensures we don't get a trailing backslash).
for %%I in ("%~dp0.") do set dirname=%%~nxI

REM -- Create the archive while respecting .gitignore --
REM    Use --prefix so that everything lands inside a top-level folder called %dirname%.
git archive --format=zip --prefix="%dirname%/" --output="%dirname%.zip" HEAD

goto :eof

REM -- Now actually run the above logic --
cd mydir
call :gitzip
