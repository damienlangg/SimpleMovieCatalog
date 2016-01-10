
set -x
RELDIR=SimpleMovieCatalog
#VER=1.2.4
VER=`sed -n 's/^.*progver.*"\(.*\)".*$/\1/p' < moviecat.pl`
ZIP=$RELDIR-$VER.zip

rm -rf $RELDIR $ZIP

svn export . $RELDIR

rm $RELDIR/makerel.sh
rm $RELDIR/interactive.cmd

unix2dos $RELDIR/*.txt $RELDIR/doc/*.txt $RELDIR/demo/*.txt
unix2dos $RELDIR/*.cmd $RELDIR/demo/*.cmd

zip -r $ZIP $RELDIR

mv $RELDIR $RELDIR-$VER

