@echo off

title Simple Movie Catalog - DEMO

perl moviecat.pl -c demo-cfg.txt
explorer demo\catalog.html

echo Press any key to exit ...
pause >NUL

