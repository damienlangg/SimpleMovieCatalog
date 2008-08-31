
set -x
RELDIR=SimpleMovieCatalog
VER=1.0.2
ZIP=$RELDIR-$VER.zip

rm -rf $RELDIR $ZIP

mkdir $RELDIR
mkdir $RELDIR/lib
mkdir $RELDIR/doc

cp moviecat.pl interactive.cmd run_scan.cmd $RELDIR

cp IMDB_Movie.pm  $RELDIR/lib

if [ -e default-cfg.txt ]; then
    cp default-cfg.txt $RELDIR/config.txt
else
    cp config.txt $RELDIR/config.txt
fi
cp readme.txt $RELDIR
cp license.txt gpl.txt todo.txt sample-cfg.txt changelog.txt  $RELDIR/doc

cp demo.cmd demo-cfg.txt $RELDIR/demo
tar cf - demo --exclude CVS --exclude '*.jpg' | tar xvf - -C $RELDIR

unix2dos $RELDIR/*.txt $RELDIR/doc/*.txt $RELDIR/demo/*.txt
unix2dos $RELDIR/*.cmd $RELDIR/demo/*.cmd

zip -r $ZIP $RELDIR

