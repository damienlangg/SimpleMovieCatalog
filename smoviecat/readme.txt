
Simple Movie Catalog 1.0.2
Copyright (C) 2008 damien.langg@gmail.com

Simple Movie Catalog will scan a given directory for movies,
query imdb for info and generate a catalog in html which offers
sorting and grouping of found movies by different criteria.



Install Instructions:
=====================

* Windows:

Simple Movie Catalog is written in perl so you'll have to first:

   1. Install Perl
      Download from: http://www.activestate.com/Products/activeperl/
      Or install cygwin, which includes perl (http://www.cygwin.com/)
      Make sure to have perl in PATH!

   2. Install Simple Movie Catalog
      Download SimpleMovieCatalog.zip and unpack to a directory of your liking.
      (example: C:\Program Files\SimpleMovieCatalog)

   3. Run
      Drag&drop a directory to run_scan.cmd or edit config.txt and start run_scan.cmd
      The directory will be scanned, html report generated and opened using your
      favorite web browser.

* Linux:

      Unpack, edit config.txt and run:
      $ perl moviecat.pl -c config.txt
      Open report/movies.html with your favorite browser.
      Read the instruction in the readme.txt file for more details. 
      Also you might want to convert all .txt files to unix format:
      $ dos2unix *.txt doc/*.txt



How does it work?
=================

The directories are scanned for .nfo and .txt files that contain links to
imdb info like this: http://www.imdb.com/title/tt0062622/
If no such link is present then the movie title and year is guessed from
directory name and searched on imdb for an exact match.
If none of the above methods produce valid info, then the directory is reported
in the "Missing Info" group.
You can then resolve missing info for these directories by either:
 - renaming the directory to reflect the "Title (Year)"
 - manually adding imdb link to a .nfo or .txt file in the directory
 - using the interactive mode to assign movies to directories
All imdb queries are cached in imdb_cache directory so running the scan
multiple times should be fast.



Command Line Options:
=====================

Brief help on command line options:

Usage: perl moviecat.pl [OPTIONS] [DIRECTORY ...]
  Options:
    -h|-help                Help (short|long)
    -V|-version             Version
    -v/q|-verbose/quiet     Verbose/Quiet output
    -c|-config <CFGFILE>    Load configuration
    -i|-interactive         Interactive mode
    -o|-out <FILENAME>      Output path base name
    -t|-title <TITLE>       Set Title (multiple to define groups)
    -g|-group               Group separator
    -s|-skip <NAME>         Skip file or dir
    -x|-regex <EXPR>        Skip using regular expressions
    -ns|-noskip             Clear preset skip lists
    -gs|-gskip <NAME>       Group Skip file or dir
    -gx|-gregex <EXPR>      Group Skip using regular expressions
    DIRECTORY               Directory to scan

  More Options:
    -a|-automatch           Auto guess and report exact matches [default]
    -na|-noautomatch        Disable auto match
    -m|-missing             Report folders with missing info [default]
    -nm|-nomissing          Don't report missing info
    -mm|-missmatch          Report guessed exact matches as missing
    -as|-autosave           Save auto guessed exact matches

  Presets:
    skip list: [sample subs subtitles cover covers]
    regex skip: [/subs-.*/ /\W*sample\W*/]
    media ext: [mpg mpeg avi mov qt wmv mkv nfo rar iso bin cue srt sub]
    codec tags: [cam ts r5 dvdscr dvdrip dvd dvd9 cd1 cd2 hdtv hddvdrip hddvd bluray bd5 bd9 vcd xvid divx x264 matroska wmv dts dolby ac3 vorbis mp3 sub 720p 1080p hd hidef]
    cache dir: [imdb_cache]
    output: [report/movies]



Config file:
============

All command line options can be used in a config file.
Use only one option per line, followed by optional arguments in same line.
Empty lines and lines starting with # are ignored.
See doc/sample-cfg.txt for an example.



Interactive mode:
=================

Start with -i option or run interactive.cmd to enter interactive mode.
In interactive mode, you can assign movies to directories which are missing
info (either missing a .nfo file or guessing didn't give an exact match).

Brief help on interactive commands:

TITLE (YEAR)    -  Search by TITLE [(YEAR) optional]
s TITLE (YEAR)  -  Search by TITLE [(YEAR) optional]
ID              -  Specify IMDB ID
URL             -  Specify IMDB URL

.               -  Show current dir info and guesses
l / ll          -  List relevant / all files
d / dd          -  List dirs (missing info / all)
dir             -  List sub-dirs to current dir
cd N/DIR        -  Change to dir number(N) / name(DIR)
<enter>         -  Next dir with missing info
n / p           -  Next / Previous dir
pwd             -  Print Current Dir
!CMD            -  Run command CMD in dir
r               -  Recreate Report
? / h / help    -  Print Help
q / quit        -  Quit



License:
========

Covered by the GPL License.
Read doc/license.txt and doc/gpl.txt for details.



