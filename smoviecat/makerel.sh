
set -x
RELDIR=SimpleMovieCatalog
VER=1.0.1
ZIP=$RELDIR-$VER.zip

rm -rf $RELDIR $ZIP
mkdir $RELDIR
cp IMDB_Movie.pm moviecat.pl    $RELDIR
cp interactive.cmd run_scan.cmd demo.cmd $RELDIR
cp readme.txt license.txt gpl.txt todo.txt sample-cfg.txt demo-cfg.txt  $RELDIR
tar cf - demo --exclude CVS --exclude '*.jpg' | tar xvf - -C $RELDIR
if [ -e default-cfg.txt ]; then
    cp default-cfg.txt $RELDIR/config.txt
else
    cp config.txt $RELDIR/config.txt
fi

zip -r $ZIP $RELDIR

