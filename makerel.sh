
set -xe
RELDIR=SimpleMovieCatalog
#VER=1.2.4
VER=`sed -n 's/^.*progver.*"\(.*\)".*$/\1/p' < moviecat.pl`
ZIP=$RELDIR-$VER.zip

rm -rf $RELDIR $ZIP

#svn export . $RELDIR
mkdir $RELDIR
git archive HEAD | tar -xf - -C $RELDIR

rm $RELDIR/makerel.sh
rm $RELDIR/.gitignore
rm -r $RELDIR/src
rm -r $RELDIR/lib/attic
rename .md .txt $RELDIR/*.md
mv $RELDIR/config-sample.txt $RELDIR/config.txt

unix2dos $RELDIR/*.txt $RELDIR/*/*.txt
unix2dos $RELDIR/*.cmd $RELDIR/*/*.cmd

zip -r $ZIP $RELDIR

mv $RELDIR $RELDIR-$VER

