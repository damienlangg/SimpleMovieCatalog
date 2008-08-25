@echo off

title Simple Movie Catalog -- Interactive

set OPT=-i

:: get script dir
for %%X in (%0) do set SDIR=%%~dpX
echo Script Dir: %SDIR%
chdir /d %SDIR%

:: check for perl
for %%X in (perl.exe) do set PERLBIN=%%~$PATH:X
if x%PERLBIN%x == xx goto :NOPERL
echo Perl: %PERLBIN%

if x%1x == xx goto :SCANCONF

perl moviecat.pl -o report\cmd %OPT%  %1 %2 %3 %4 %5 %6 %7 %8 %9
if ERRORLEVEL 1 goto :ERROR
explorer report\cmd.html
goto :EXIT

:SCANCONF

perl moviecat.pl -c config.txt %OPT%
if ERRORLEVEL 1 goto :ERROR
explorer report\movies.html
goto :EXIT

:NOPERL

echo ********************************
echo ERROR: Perl not found!
echo Install Perl and add it to PATH!
echo ********************************
goto :EXIT

:ERROR

echo ERROR running moviecat.pl: %ERRORLEVEL%

:EXIT

echo Press any key to exit ...
pause >NUL


