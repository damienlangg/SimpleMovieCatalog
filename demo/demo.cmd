@echo off

title Simple Movie Catalog - DEMO

cd ..
perl moviecat.pl -c demo\demo-cfg.txt
explorer demo\catalog.html

echo Press any key to exit ...
pause >NUL

