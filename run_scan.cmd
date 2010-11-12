@echo off

:: If perl is not in PATH, uncomment and edit the following line:
:: PATH=%PATH%;C:\Perl\bin

title Simple Movie Catalog

set OPT=

:: check for perl
perl -e exit
if %ERRORLEVEL% NEQ 0 goto :NOPERL
perl -e "print(\"Perl: \",$^X,\" \",$^V,\" \",$^O,\"\n\")"

:: get script dir
for %%X in (%0) do set SDIR=%%~dpX
echo Script Dir: %SDIR%
chdir /d %SDIR%

:: check arguments
if x%1x == xx goto :SCANCONF

:: use arguments
perl moviecat.pl -o report\cmd %OPT% %1 %2 %3 %4 %5 %6 %7 %8 %9
if %ERRORLEVEL% NEQ 0 goto :ERROR
explorer report\cmd.html
goto :EXIT

:: use conf file
:SCANCONF
perl moviecat.pl -c config.txt %OPT%
if %ERRORLEVEL% == 10 goto :NODIR
if %ERRORLEVEL% NEQ 0 goto :ERROR
explorer report\movies.html
goto :EXIT

:: error handling

:NOPERL
echo.
echo ******************************************
echo ERROR: Perl not found!
echo Install Perl and add it to PATH
echo Or edit %0 and specify Perl path
echo ******************************************
echo.
explorer http://www.activestate.com/Products/activeperl/
goto :EXIT

:NODIR
echo.
echo Edit config file and re-run.
echo.
explorer config.txt
goto :EXIT

:ERROR
echo ERROR running moviecat.pl: %ERRORLEVEL%

:EXIT
echo Press any key to exit ...
pause >NUL


