#!/usr/bin/perl

=copyright

    Simple Movie Catalog 1.9.1
    Copyright (C) 2008-2013 damien.langg@gmail.com

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut


use strict;
use Cwd;
use FindBin;
use File::Find;
use File::Basename;
use File::Copy;
use File::stat qw(); # no-override
use LWP::Simple;

#use Term::ReadKey qw(GetTerminalSize);
my $have_term = eval 'use Term::ReadKey; 1';

#use Time::HiRes qw(time);
my $hires_time = sub { time(); };
if (eval 'use Time::HiRes; 1') {
    $hires_time = \&Time::HiRes::time;
}
my $g_stime = $hires_time->();

#use IMDB_Movie;
push @INC, $FindBin::Bin;
push @INC, $FindBin::Bin . "/lib";
require "IMDB_Movie.pm";

### Globals

# override download function
$IMDB::Movie::download_func = \&cache_imdb_id;

my $progver = "1.9.1";
my $progbin = "moviecat.pl";
my $progname = "Simple Movie Catalog";
my $progurl = "http://smoviecat.sf.net/";
my $author = 'damien.langg@gmail.com';
my $copyright = "Copyright 2008-2013, $author";

my $prog_dir = $FindBin::Bin;
my $imdb_cache = "$prog_dir/imdb_cache";
my $scan_log = "$prog_dir/scan.log";
my $image_dir = "images";
my $image_cache;
my $max_cache_days = 90; # keep cache for up to 3 months
my $base_path = "report/movies";
my $base_name;
my $base_dir;
my $jsname = "moviecat.js";

my @parse_ext = qw( nfo txt url desktop );

my @video_ext = qw( mpg mpeg mpe mp4 avi mov qt wmv mkv iso bin cue ratdvd tivo ts divx );

my @media_ext = (@video_ext, qw( vob nfo rar srt sub ));

my @hidef = qw( hidef hd hdtv hddvdrip hddvd bluray bd5 bd9
                720 720p 720i 1080 1080p 1080i );

my @codec = (@hidef, qw(
        cam ts r5 dvdscr dvdrip dvd dvd9 cd1 cd2
        vcd xvid divx x264 matroska wmv
        dts dolby ac3 vorbis mp3 sub
        ));

# series: s01e02 / season 1 / episode 2 / 1x2
my @series_tag = ( 's\d{1,2}e\d{1,2}', 'season\W+\d+', 'episode\W+\d+', '\d+x\d+' );

my @subsearch = (
        "http://opensubtitles.org/en/search2/sublanguageid-eng/moviename-%TITLE%",
        "http://subscene.com/filmsearch.aspx?q=%TITLE%",
        "http://podnapisi.net/ppodnapisi/search?tbsl=1&asdp=0&sJ=2&sY=&sAKA=1&sK=%TITLE%",
        "http://divxtitles.com/%TITLE%/English/any/1",
        "http://www.subtitlesource.org/title/tt%ID%",
        # "http://www.subtitlesource.org/search/%TITLE%",
        );

my @opt_links = (
        "Trailers=http://www.imdb.com/title/tt%ID%/trailers",
        "http://www.youtube.com/results?search_query=%TITLE%",
        "http://www.rottentomatoes.com/search/full_search.php?search=%TITLE%",
        # "http://www.google.com/search?q=%TITLE%",
        # "http://en.wikipedia.org/wiki/Special:Search?search=%TITLE%",
        );

my @opt_user; # list of users vote history urls
my @user_vote;

my $opt_i = 0; # interactive
my $opt_auto = 1;       # Auto guess and report exact matches
my $opt_miss = 1;       # Report folders with missing info
my $opt_miss_match = 0; # Report guessed exact matches as missing
my $opt_match_first = 0;# Match first if multiple matches exists
my $opt_match_year = 0; # Match also folders with missing year
my $opt_match_fname = 1;# Match file names
my $opt_auto_save = 0;  # Save auto guessed exact matches
my $opt_group_table = 1;# use table for groups
my $opt_xml = 0;        # xml export
my $opt_js = 1;         # javascript sort & filter
my $opt_aka = 0;        # search AKA titles
my $opt_theme = 'white'; # default theme
my $opt_otitle = 0;     # original title
my $verbose = 1;
my $columns = 80;

my %movie;  # movie{id}
my @group;  # group list - array of ptr to mlist
my $ngroup;
my $pgroup; # ptr to current group
my $pmlist; # current group movie list - ptr to hash
my %all_dirs;   # visited dirs
my $ndirs;
# global skip: sample subs subtitles
my @skiplist = qw( sample subs subtitles cover covers );
my @rxskiplist = qw( /subs-.*/ /\W*sample\W*/ );
my @ignorelist; # ignore dir with missing info, not recursive 
my %gbl_tags;
# @{$gbl_tags{"TAG"}{pattern}}
# ${$gbl_tags{"TAG"}{order}} : sorted<0, user>0, hidef=90, imdb=100, guess=110

@{$gbl_tags{"HiDef"}{pattern}} = @hidef;
$gbl_tags{"HiDef"}{order} = 90;

my $F_HTML;
my $F_LOG;
my $last_cache_valid;

### Setup

$| = 1; # autoflush stdout

### Utility Funcs

sub print_html {
    print $F_HTML @_, "\n";
}

sub print_level {
    return if (shift > $verbose);
    print @_;
}

sub print_log {
    my $line = join '', @_;
    chomp $line;
    # print_level 2, $line, "\n";
    my $stamp = sprintf "[ %.6f ] ", ($hires_time->() - $g_stime);
    print $F_LOG $stamp, $line, "\n";
}

sub print_error {
    print_log "ERROR: ", @_;
    print "ERROR: ", @_, "\n";
}

sub print_info {
    print_log "INFO: ", @_;
    print @_;
}

sub print_note {
    print_log "NOTE: ", @_;
    print_level 1, @_;
}

sub print_detail {
    print_log "DETAIL: ", @_;
    print_level 2, @_;
}

sub print_debug {
    print_log "DEBUG: ", @_;
    print_level 3, @_;
}

sub _print_debug {
    print @_, "\n";
}

sub abort {
    print_error @_;
    die;
}

sub unique {
    my %seen;
    grep(!$seen{$_}++, @_);
}

sub unique_icase {
    my %seen;
    grep(!$seen{lc($_)}++, @_);
}

sub match_ext
{
    my ($name, @ext) = @_;
    grep { $name =~ /\.$_$/i } @ext;
}

sub match_ext_list
{
    my @match;
    for my $name (@_) {
        if (match_ext($name, @media_ext)) {
            push @match, $name;
        }
    }
    return @match;
}

sub cut_ext {
    my $f = shift;
    $f =~ s/\.\w+$//;
    return $f;
}

sub cut_ext_l {
    my @l;
    for my $f (@_) { push @l, cut_ext($f); }
    return @l;
}

# normalize path
# internal path representation uses /
sub normal_path {
    my $path = shift;
    $path =~ tr[\\][/];
    return $path;
}

# sort by alphanum, ignore case
sub by_alpha {
    lc($a) cmp lc($b);
}

# config error
sub exit_cfg {
    exit 10;
}

###############################

### Scan


sub getfile {
  my $filename = shift;
  my $F;
  open $F, "<", $filename or return undef;
  my $contents;
  {
    local $/ = undef;     # Read entire file at once
    $contents = <$F>;     # Return file as one single `line'
  }                       # $/ regains its old value
  close $F;
  return \$contents; # return reference
}

sub valid_cache
{
    my $fname = shift;
    $last_cache_valid = 0;
    return 0 unless -e $fname;
    my $age = -M _; # age in days
    my $valid = $age <= $max_cache_days;
    print_debug "Cache age: ",
                sprintf("%.0f ", $age), #sprintf("%.1f ", $age),
                ($valid?"(ok)":"(too old)"), " '$fname'";
    $last_cache_valid = $valid;
    return $valid;
}

sub cache_imdb_id
{
    my $id = shift;

    my $html_file = $imdb_cache . "/imdb-$id.html";
    my $html;
    if (valid_cache($html_file) and $html = getfile($html_file)) {
        print_debug "Using Cached: $html_file\n";
        print_note " ";
    } else {
        print_debug "Connecting to IMDB... ($id)\n";
        print_note ".";
        unlink $html_file if -e $html_file;
        $html = IMDB::Movie::download_page_id($id);
        if (!$html) {
            print_debug "Error getting page: $id\n";
            return undef;
        }
        my $F_CACHE;
        if (open $F_CACHE, ">", $html_file) {
            print_debug "Write Cache: $html_file\n";
            print $F_CACHE $html;
            close $F_CACHE;
        } else {
            print_log "Error Writing Cache: $html_file\n";
        }
    }

    return $html;
}

sub cache_imdb_find
{
    my ($title, $year) = @_;

    my $fname = lc("$title ($year)");
    $fname =~ tr[:/\\][-];
    my $html_file = $imdb_cache . "/imdb_find".($opt_aka?"_aka":"")."-$fname.html";
    my $html;
    if (valid_cache($html_file) and $html = getfile($html_file)) {
        print_debug "Using Cached: $html_file\n";
        print_note " ";
    } else {
        print_debug "Connecting to IMDB...\n";
        print_note ".";
        unlink $html_file if -e $html_file;
        $html = IMDB::Movie::get_page_find($title, $year);
        if (!$html) {
            print_debug "Error getting page: $title ($year)\n";
            return undef;
        }
        my $F_CACHE;
        if (open $F_CACHE, "> $html_file") {
            print_debug "Write Cache: $html_file\n";
            print $F_CACHE $html;
            close $F_CACHE;
        } else {
            print_log "Error Writing Cache: $html_file\n";
        }
    }

    return $html;
}

sub img_name
{
    my $id = shift;
    return "imdb-" . $id . ".jpg";
}

sub cache_image
{
    my $m = shift;
    if (!$m or !$m->id or (!$m->img and (!$m->photos or !$m->photos->[0]))) {
        print_note "-";
        return 1;
    }
    if (!$m->img and $m->photos and $m->photos->[0]) {
        # use first gallery photo if no poster
        print_debug "No poster found - using first photo '", $m->photos->[0], "'";
        $m->{img} = $m->photos->[0];
    }
    my $img_file = $image_cache . "/" . img_name($m->id);
    # only refresh image cache if html cache changed
    if ($last_cache_valid and -e $img_file) {
        print_note " ";
        return 1;
    }
    print_note ".";
    my $image = get($m->img);
    if (!$image) {
        print_error "Getting image: ", $m->img, "";
        return 0;
    }
    my $F_IMG;
    if (open $F_IMG, ">:raw", $img_file) {
        print_debug "Write Image Cache: $img_file\n";
        print $F_IMG $image;
        close $F_IMG;
    } else {
        print_error "Saving image: ", $img_file, "";
        return 0;
    }
    return 1;
}

sub cache_movie
{
    my $m = shift;
    if ($opt_otitle) {
        if ($m->{otitle} and !defined($m->{rtitle})) {
            $m->{rtitle} = $m->{title}; # save regional title
            $m->{title} = $m->{otitle}; # use original title
        }
    }
    $movie{$m->id} = $m;
    cache_image($m);
}

sub getmovie
{
    my $id = shift;
    my $m = $movie{$id};

    if ($m) { return $m;}

    my $html = cache_imdb_id($id);
    if (!$html) {
        print_log "*** Error: get imdb $id\n";
        print_note " FAIL1";
        return undef;
    }
    $m = IMDB::Movie->new_html($id, $html);
    if (!$m) {
        print_log "*** Error: parse imdb $id\n";
        print_note " FAIL2";
        return undef;
    }
    cache_movie($m);
    return $m;
}

sub match_title
{
    my ($t1, $t2) = @_;
    # print_debug "\nT1: $t1 T2: $t2\n";
    $t1 = lc($t1);
    # remove non-alphanums/keep space
    # $t1 =~ s/[^\w ]//g;
    # remove non-alphanums
    $t1 =~ s/\W//g;
    $t2 = lc($t2);
    $t2 =~ s/\W//g;
    #print_debug "\nT1: $t1 T2: $t2\n";
    return $t1 eq $t2;
}

sub match_m_title
{
    my ($title, $m) = @_;
    if ($m->{otitle} and match_title($title, $m->{otitle})) { return 1; }
    if ($m->{rtitle} and match_title($title, $m->{rtitle})) { return 1; }
    return match_title($title, $m->{title});
}

sub findmovie
{
    my ($title, $year, $type) = @_;
    my $html = cache_imdb_find($title, $year);
    if (!$html) {
        print_log "*** Error: find imdb '$title' ($year)\n";
        print_note " FAIL\n";
        return undef;
    }
    my @matches = IMDB::Movie::get_matches($html);
    my $m;
    if (@matches) {
        # if type specified, find first matching type
        if ($type) {
            my $i;
            for $i (0 .. $#matches) {
                print_log "match[$i] = ", $matches[$i]->{id},
                          " ", $matches[$i]->{title},
                          " (", $matches[$i]->{year},
                          ") [", $matches[$i]->{type}, "]\n";
                # if year known it has to match too
                if ($year and ($year != $matches[$i]->{year})) { next; }
                if ($matches[$i]->{type} =~ /$type/) {
                    print_log "match type: $title ($year) [$type]\n";
                    # move $i to first place
                    @matches = ($matches[$i], splice(@matches, $i, 1));
                    last;
                }
            }
        }
        # search result - cache first hit
        if ($matches[0]->{id}) {
            $m = getmovie($matches[0]->{id});
            if ($m) {
                # add match list
                $m->{matches} = \@matches;
                # not a direct hit! unless title matches (almost) exactly
                if (match_m_title($title, $m)) {
                    print_debug("Search '$title' ($year) Exact Match: ".$m->id." ".$m->title);
                    $m->{direct_hit} = 1;
                } else {
                    # if type matches then accept
                    if ($type and $m->type =~ /$type/i) {
                        $m->{direct_hit} = 1;
                    } else {
                        $m->{direct_hit} = 0;
                    }
                }
                return $m;
            } else {
                print_log "ERR: ", $matches[0]->{id}, "\n";
            }
        }
    }
    # direct hit or no match
    $m = IMDB::Movie->new_html(0, $html);
    if (!$m) {
        print_log "*** Error: parse imdb '$title' ($year)\n";
        return undef;
    }
    print_debug("Search '$title' ($year) Direct Hit: "
            .$m->{direct_hit}." id:".$m->id." t:".$m->title);
    cache_movie($m);
    return $m;
}

sub save_movie
{
    my ($dir, $movie) = @_;
    my $fname;
    my $F_INFO;
    $fname = $movie->{title}." (".$movie->year.")";
    $fname =~ s/[\/\\:]/-/g;
    $fname =~ tr/<>/()/;
    $fname = "$dir/$fname - imdb.nfo";
    print_info "Saving: $fname\n";
    if (!open $F_INFO, ">", $fname) {
        print_error "Opening '$fname'";
        return;
    }
    print $F_INFO "# Generated by $progname $progver #\n\n";
    print $F_INFO $movie->title, " (", $movie->year, ") ", $movie->type, "\n";
    print $F_INFO IMDB::Movie::get_url_id($movie->id), "\n\n";
    close $F_INFO;
}


sub shorten
{
    my $name = shift;
    my $max = $columns - 20; #60;
    my $sep = "~~";
    if (length($name) > $max) {
        my ($l1, $l2, $l3);
        $l2 = length($sep);
        $l1 = int (($max - $l2) / 2);
        $l3 = $max - $l1 - $l2;
        $name = substr($name, 0, $l1) . $sep . substr($name, -$l3, $l3);
    } else {
        $name = sprintf("%-".$max."s", $name);
    }
    return "$name ";
}

sub open_bom
{
    my $fname = shift;

    my ($bom, $FH);
    open $FH, "<", $fname;
    read $FH, $bom, 2;
    if ($bom eq "\x{fe}\x{ff}" or $bom eq "\x{ff}\x{fe}") {
        # print_debug "UNICODE UTF-16: $fname\n";
        seek $FH, 0, 'SEEK_SET';
        binmode $FH, "encoding(UTF-16)";
    }
    return $FH;
}


sub get_dirent
{
    my ($dir, $fname) = @_;
    my $dirent = $fname ? \%{$all_dirs{$dir}->{file}{$fname}} : \%{$all_dirs{$dir}};
    return $dirent;
}

sub split_location
{
    my $path = shift;
    if ($path =~ /[\/\\]$/) {
        chop $path;
        return ($path);
    }
    if (exists $all_dirs{$path}) {
        return ($path);
    }
    my $dir = dirname($path);
    my $fname = basename($path);
    return ($dir, $fname);
}

sub get_dirent_location
{
    my $path = shift;
    my ($dir, $fname) = split_location($path);
    return get_dirent($dir, $fname);
}

sub dir_assign_movie
{
    my ($dir, $movie, $fname) = @_;
    my $id = $movie->id;
    my $dirent = get_dirent($dir, $fname);
    $dirent->{info} = 1;
    $dirent->{id}{$id} = 1; # $movie
    if ($dirent->{mtime}) {
        print_debug "Existing mtime: $dir/$fname, ", $dirent->{mtime};
    } else {
        my $path = $fname ? "$dir/$fname" : $dir;
        $dirent->{mtime} = File::stat::stat($path)->mtime;
        print_debug "mtime: $dir/$fname, ", $dirent->{mtime};
    }
}

sub group_assign_tag
{
    my ($id, $tag, $ord) = @_;
    if (!$pmlist->{$id}->{tag}{$tag}) {
        $pmlist->{$id}->{tag}{$tag} = 1;
        $pgroup->{tag}{$tag}++;
    }
    if (!$gbl_tags{$tag}{order}) {
        $gbl_tags{$tag}{order} = $ord;
    }
}

sub group_assign_movie
{
    my ($path, $movie) = @_;
    my $id = $movie->id;
    $pmlist->{$id}->{movie} = $movie;
    $pmlist->{$id}->{location}{$path}++;
    # match path tags
    my $lcpath = lc(normal_path($path));
    for my $tag (keys %gbl_tags) {
        for my $pat (@{$gbl_tags{$tag}{pattern}}) {
            $pat = lc(normal_path($pat));
            if (index($lcpath, $pat) >= 0) {
                group_assign_tag($id, "$tag");
                last;
            }
        }
    }
    # imdb movie type to tag
    if ($movie->type =~ /series/i) {
        group_assign_tag($id, "Series", 100);
    } elsif ($movie->type =~ /vg/i) {
        group_assign_tag($id, "VideoGame", 100);
    } elsif ($movie->type =~ /video/i) {
        group_assign_tag($id, "Video", 100);
    } elsif ($movie->type =~ /tv/i) {
        group_assign_tag($id, "TV", 100);
    } elsif ($movie->type =~ /\bv\b/i) { # \b = word boundary
        group_assign_tag($id, "Video", 100);
    } elsif ($movie->type) {
        group_assign_tag($id, $movie->type, 100);
    }
}


sub count_loc
{
    my $id = shift;
    my $num_loc = 0;
    return unless $pmlist->{$id};
    for my $nl (values %{$pmlist->{$id}->{location}}) { $num_loc += $nl; }
    return $num_loc;
}


sub parse_nfo
{
    my ($fdir, $fname) = @_;

    print_debug "PARSE: $fname\n";
    my $shortname = shorten($fname);
    my $found = 0;
    my $F_NFO = open_bom $fname;
    while (<$F_NFO>) {
        if (/imdb\.com\/title\/tt(\d+)/i) {
            my $id = $1;
            $found++;
            if ($found>1) {
                $shortname = shorten(" +++ ($found) " . $fname . "");
            }
            print_detail "$fname: $id\n";
            print_note "$shortname: $id";
            my $m;
            if ($pmlist->{$id}) {
                $m = $pmlist->{$id}->{movie};
            } else {
                $m = getmovie($id);
            }
            if (!$m) {
                # print failure?
                print_note "\n";
                next;
            }
            dir_assign_movie($fdir, $m);
            group_assign_movie($fdir, $m);
            my $num_loc = count_loc($id);
            if ( $num_loc > 1 ) { print_note "*$num_loc"; }
            print_note " OK\n";
        }
    }
    close $F_NFO;
    if (!$found) {
        print_detail "$fname: IMDB NOT FOUND\n";
        print_note "$shortname: IMDB NOT FOUND\n";
    }
}


my $END_DIR_MARK = "...END...";

# find process (wanted)
sub process_file
{
    my $fname = $File::Find::name;
    print_debug "PROCESS: '$fname'\n";
    if (substr($fname, -1-length($END_DIR_MARK)) eq "/$END_DIR_MARK") {
        # filter will append this as the last entry in dir.
        # this is better done here than in post-process,
        check_dir_info($File::Find::dir);
        return;
    }
    if (match_ext($fname, @parse_ext) and -f $fname) {
        parse_nfo($File::Find::dir, $fname);
    }
}

sub match_path
{
    my ($dir, $name, $match) = @_;
    my $cmpname;
    # equalize slashes
    $match = normal_path($match);
    if ($match =~ m{/}) {
        # slash in match name, use last part of full path name
        my $path = "$dir/$name";
        $cmpname = substr($path, -length($match));
        #print_debug "Skip-search path: $match in: $cmpname\n";
    } else {
        $cmpname = $name;
    }
    # ignore case
    return (lc($cmpname) eq lc($match));
}

# find preprocess
sub filter_dir
{
    my @list;
    my $visited = $all_dirs{$File::Find::dir}->{visited};
    # if already visited in previous group, just copy info.
    if ($visited) {
        print_debug "RE-VISITED: $File::Find::dir\n";
        for my $id (keys %{$all_dirs{$File::Find::dir}->{id}}) {
            group_assign_movie($File::Find::dir, $movie{$id});
            print_debug "RE-VISITED: $File::Find::dir : $id\n";
            print_note shorten("$File::Find::dir/"), ": $id (re)\n";
        }
    } else {
        print_debug "VISITED: $File::Find::dir\n";
        $all_dirs{$File::Find::dir}->{visited} = 1;
    }
    print_debug "FILTER: @_\n";
    for my $name (@_) {
        next if ($name eq "." or $name eq "..");
        my $skip = 0;
        #my $fname = normal_path($File::Find::dir . "/" . $name);
        my $fname = "$File::Find::dir/$name";
        # only stat file once
        my $f_is_dir = -d $fname;
        my $f_is_file = -f _; # _ is previous stat
        # if already visited, pass through only directories,
        # no need to process files again.
        next if ($visited and ! $f_is_dir);

        # print_debug "filter check: $name\n";
        for my $s (@{$pgroup->{skiplist}}, @skiplist) {
            if (match_path($File::Find::dir, $name, $s)) {
                $skip = 1;
                last;
            }
        }
        # append "/" to dirs
        my $fnamex = $fname;
        if ( $f_is_dir ) { $fnamex .= "/"; }
        for my $re (@{$pgroup->{rxskiplist}}, @rxskiplist) {
            # ignore case
            # use (?-i) in regex to force case sensitive
            if ($fnamex =~ /$re/i) {
                #print_debug "SKIP RegEx: $re path: $fname\n";
                $skip = 1;
                last;
            }
        }
        if ($skip) {
            print_note shorten(" --- " . $fname), ": SKIP\n";
        } else {
            # is file?
            if ($f_is_file) {
                # is relevant media file?
                if (match_ext($name, @media_ext)) {
                    $all_dirs{$File::Find::dir}->{relevant}->{$name} = 1;
                }
                # has to be parsed?
                if (match_ext($name, @parse_ext)) {
                    push @list, $name;
                }
            }
            # directory
            elsif ($f_is_dir) {
                push @list, $name;
            }
        }
    }
    # append a special marker to end of list, so that process_files
    # will try to autoguess if no info is found.
    push @list, $END_DIR_MARK;
    
    return @list;
}

# check if info can be inherited from parent
# Cases:
#  dir/name.rar dir/name/file.avi
#  dir/cd[12]/file.avi
# note: find() processes files in a dir first, then follows subdirs,
# so it's safe to assume the subdir has had all files processed already.
sub inherit
{
    my ($dir, $parent) = @_;
    return 0 unless ($all_dirs{$parent}->{info});
    print_note shorten("$dir/"), ": Inherit\n";
    $all_dirs{$dir}->{info} = $all_dirs{$parent}->{info};
    $all_dirs{$dir}->{id} = $all_dirs{$parent}->{id};
    $all_dirs{$dir}->{mtime} = $all_dirs{$parent}->{mtime};
    for my $id (keys %{$all_dirs{$parent}->{id}}) {
        if ($pmlist->{$id}) {
            # inherit only if present in current group
            $pmlist->{$id}->{location}{$dir}++;
        }
    }
    return 1;
}


sub automatch1
{
    my ($dir, $fname) = @_;
    my $path = "$dir/$fname";
    my ($title, $year, $type, $ccount) = path_to_guess($fname ? cut_ext($fname) : $dir);
    return 0 if (!$title); 
    return 0 if (!$opt_match_year and !$year and !$type and ($ccount < 2)); 
    my $dirent = get_dirent($dir, $fname);
    print_note shorten($path), ": GUESS\n";
    print_note shorten(" ??? Guess: '".$title."' (".$year.")".($type?" [$type]":"")), ": ";
    my $msearch = findmovie($title, $year, $type);
    if (!$msearch && $year) {
        # no match found, retry without year
        $msearch = findmovie($title, 0, $type);
    }
    if ($msearch and $msearch->id and
           ($msearch->direct_hit or $opt_match_first))
    {
        print_note $msearch->id, " MATCH\n";
        dir_assign_movie($dir, $msearch, $fname);
        if (!$opt_miss_match) {
            group_assign_movie($path, $msearch);
        }
        if ($opt_auto_save) {
            save_movie($dir, $msearch);
        } else {
            $dirent->{guess} = 1;
            group_assign_tag($msearch->id, "Guess", 110);
        }
        return 1 if ($msearch->direct_hit);
        # return 1 if direct hit

    } elsif ($msearch) {
        my $nmatch = scalar @{$msearch->matches};
        print_note "Matches: $nmatch\n";
        $dirent->{matches} = $nmatch;
        $dirent->{matchlist} = $msearch->matches;
    } else {
        $dirent->{matches} = 0;
        print_note "No Match\n";
    }
    return 0;
}



sub automatch
{
    my $dir = shift;
    print_debug "AUTOMATCH: $dir";
    return if (automatch1($dir));
    return unless ($opt_match_fname);
    # not direct hit and match_fname enabled:
    # search through relevant files
    return unless ($all_dirs{$dir}->{relevant});
    my $fn;
    for $fn (keys %{$all_dirs{$dir}->{relevant}}) {
        if (match_ext($fn, @video_ext)) {
            print_debug("filename guess: $dir/$fn");
            automatch1($dir, $fn);
        }
    }
}

# find postprocess
sub check_dir_info
{
    my $path = shift;
    # my ($dir, $parent) = fileparse($path);
    my $parent = dirname($path);
    my $dir = basename($path);
    print_debug "CHECK DIR: '$parent' '$dir' $path\n";
    return if (!$parent or $dir eq ".");
    # if already visited, no need to guess again
    return if ($all_dirs{$path}->{info});
    return if (!$all_dirs{$path}->{relevant});
    # check for rar, nfo, cd1/cd2, VIDEO_TS
    my $rar = "$parent/$dir.rar";
    my $nfo = "$parent/$dir.nfo";
    if ( -e $rar or -e $nfo 
         or $dir =~ /^cd\d$/i
         or uc($dir) eq "VIDEO_TS" )
    {
        if (inherit($path, $parent)) { return; }
    }
    # automatch
    if ($opt_auto) {
        automatch($path);
    }
}

sub postprocess_dir
{
    check_dir_info($File::Find::dir);
}

sub do_scan
{
    for my $g (@group) {
        $pgroup = $g; # set current group
        $pmlist = \%{$g->{mlist}}; # current group mlist
        for my $dir (@{$g->{dirs}}) {
            print_note "\n";
            print_info "[ ", $g->{title}, " ] Searching ... $dir\n";
            if ( ! -d $dir ) {
                print_error "Directory not found: '$dir'";
                exit_cfg;
            }
            find( { preprocess  => \&filter_dir,
                    wanted      => \&process_file,
                    # postprocess => \&postprocess_dir,
                    no_chdir    => 1 },
                    $dir);
        }
        print_info "Movies found: ", scalar keys %{$pmlist}, "\n";
    }
    print_note "\n";
}


###############################

### User Votes


sub get_user_votes
{
    return unless (@opt_user);
    print_info "User votes...\n";
    for my $u (@opt_user) {
        print_note "Getting: $u ...\n";
        my $newuser;
        if ($u =~ s/^([\w\s'-]+)=//) {
            $newuser = $1;
        }
        my $uv = undef;
        if (not ($u =~ /^http:/i) and not ($u =~ /^\d+$/) and -e $u) {
            # not url and not ID - it's a file
            if (my $votefile = getfile($u)) {
                $uv = IMDB::Movie::parse_vote_history($votefile);
                if ($uv) {
                    $uv->{'url'} = $u;
                }
            }
        } else {
            $uv = IMDB::Movie::get_vote_history($u);
        }
        if (!$uv) {
            print_note "Error getting $u\n";
        } else {
            if ($newuser) {
                $uv->{'name'} = $newuser;
            } else {
                $uv->{'name'} = $uv->{'user'};
            }
            print_note "User: ", ($newuser? "$newuser=" : ""), $uv->{'user'},
                    " Votes: ", scalar keys %{$uv->{'vote'}}, "\n";
            push @user_vote, $uv;
        }
    }
    print_info "\n";
}


###############################

### HTML Report


# start the HTML
#print start_html(-title=>'Movie Catalog', -bgcolor=>'lightgrey');
sub html_start
{
print_html << 'HTML_START';
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en-US" xml:lang="en-US">
HTML_START
}

sub html_head
{
    my $title = shift;
    my $bgcolor = shift || "lightgrey";

    print_html "<head>";
    print_html "<title>$title</title>";
    print_html "<meta http-equiv=\"Content-Type\""
        . " content=\"text/html; charset=iso-8859-1\">";
    if ($opt_js) {
        print_html "<script src=\"$jsname\" type=\"text/javascript\"></script>";
    }
    # CSS style
    for my $tfile (glob "$prog_dir/lib/*.css") {
        my $theme;
        if ($tfile =~ /^.*[\/\\](.*)\.css$/) {
            $theme = $1;
        } else {
            next;
        }
        my $sel = ($theme eq $opt_theme);
        print_html '<link type="text/css" rel="'
            . ($sel?'':'alternate ') . 'stylesheet" '
            . 'href="'.$theme.'.css" title="'.$theme.'">';
    }

print_html "<link href='http://fonts.googleapis.com/css?family=Open+Sans:300italic,400italic,600italic,700italic,800italic,400,300,600,700,800' rel='stylesheet' type='text/css'>";

    print_html '<link rel="icon" href="favicon_32x32.ico" type="image/gif" />
<link rel="shortcut icon" href="favicon_32x32.ico" type="image/x-icon" />';

    print_html "<style type=text/css><!--";
    print_html "span.HOVER_ULN:hover {text-decoration: underline}";
    print_html "a.HOVER_BOLD:hover {font-weight: bold}";
    print_html "input[type=text] {font-size: small; height: 1em;}";
    # print_html "table {border: outset;}";
    print_html "input[type=checkbox] {margin: 0px; width:13px; height:13px;}";
    print_html "input[type=radio] {margin: 0px; width:13px; height:13px;}";
    print_html "span.MDIRTIME {display: none}";
    print_html "--></style>";

    print_html "</head>";
    print_html "<body bgcolor=\"$bgcolor\">";
}

sub format_html_path
{
    my $path = shift;
    my $link = $path;
    $link =~ s/([\/\\])/$1<wbr>/g;
    # on windows use \ separator ($^O: cygwin MSWin32 linux...)
    # if ($link =~ /\\/) {
    if ($^O =~ /win/i) {
        $link =~ tr[/][\\];
    }
    # if file, link to dir
    my ($dir, $fname) = split_location($path);
    #return "<a href=\"file://$path\" style=word-wrap:break-word>$link</a>";
    return "<a href=\"file://$dir\">$link</a>";
}

sub format_links
{
    my ($m, $strip_tld, @links) = @_;
    my $id = $m->id;
    my $year = $m->year;
    my $title = $m->title;
    $title =~ s/ /+/g;
    for my $link (@links) {
        my $site = $link;
        my $url = $link;
        if ($link =~ /^(.+)=(https?:\/\/.+$)/) {
            $site = $1;
            $url = $2;
        } elsif ($link =~ /^https?:\/\/(www\.)?([^\/]+)/) {
            $site = $2;
            if ($strip_tld) {
                $site =~ s/^(.*\.)?([^.]+)\.[^.]+$/\2/;
                $site = ucfirst($site);
            }
        }
        $url =~ s/%ID%/$id/g;
        $url =~ s/%YEAR%/$year/g;
        $url =~ s/%TITLE%/$title/g;
        # print_html "[<a href=\"", $url, "\">$site</a>]&nbsp;";
        print_html "<a class=HOVER_BOLD href=\"", $url, "\">$site</a>&nbsp;";
    }
}

sub format_movie_id
{
    my $id = shift;
    format_movie($pmlist->{$id}->{movie},
            [ keys %{$pmlist->{$id}->{location}} ],
            [ keys %{$pmlist->{$id}->{tag}} ] );
}

sub format_movie
{
    my ($m, $loc_ref, $tag_ref) = @_;

    my @location = $loc_ref ? @{$loc_ref} : ();
    my @tags     = $tag_ref ? @{$tag_ref} : ();

    #print_debug "LOC: ", join ("\n+++", @location), "\n";

    print_html "<table width=100% cellspacing=0 class=movietable>";
        # border=1 frame=border rules=all

    print_html '<tr class="movietr">';

        my $img_file = img_name($m->id);
        my $img_link = $image_dir ."/". $img_file;
        if ( ! -e $image_cache ."/". $img_file ) { $img_link = $m->img; }
        print_html '<td class="poster poster_', $m->id ,'">';
    print_html '<img src="', $img_link, '" /><div class="frame"><div class="info"><span class=titletitle>', $m->title ,'</span><span class=titleyear>', $m->year, '</span>'; my ($runtime) = $m->runtime; my $nloc = scalar @location; print_html '<span class=titleruntime>', $runtime ? $runtime : "?" ,' min</span><span class=loc>', @location ,'</span><span class=imdb2><a href=http://www.imdb.com/title/tt', $m->id, ' target=_blank>imdb</a></span></div></div><div class=base-shadow></div></td>';

    # style=\"padding-left: 10px\"
    print_html '<td class="title absoluted"><b>';
    print_html "<h1><a class=MTITLE href=http://www.imdb.com/title/tt",
               $m->id, ">", $m->title, "</a> <span class=vuosi> <span class=MYEAR>", $m->year, "</span></span></h1>";
 #   print_html " <small><i>", $m->type, "</i></small>";
    print_html "</td></tr>";

    my ($runtime) = $m->runtime; #split '\|', $m->runtime;
    print_html '<tr class="moviedesc"><td class="hidden absoluted">';
    print_html "<span class=movieheadmeta><span class=rating info><b class=MRATING>", $m->user_rating, "</b>/10</span>",
            "<span class=runtime info><b class=MRUNTIME>", $runtime ? $runtime : "?" , "</b> min</span>",
            "<span class=genre info><i class=MGENRE>", join(' / ',@{$m->genres}), "</i></span></span>";
    # user votes
    my $found_vote = 0;
    my $uid;
    for my $uv (@user_vote) {
        $uid++;
        my $vote = $uv->{'vote'}{$m->id};
        if ($vote) {
            if (!$found_vote) {
                $found_vote = 1;
                print_html "<br><small>"; #"User: ";
            }
            print_html " ", $uv->{'name'}, ": ",
                      "<span class=MUV$uid>",  $vote, "</span> ";
            $uv->{'count'}++;
        }
    }
    if ($found_vote) {
        print_html "</small>";
    }
    print_html "</td></tr>";

    print_html '<tr class="moviedesc"><td class="plot absoluted">
    <span class="imdb-rating"><span>', $m->user_rating, '</span></span>
    ';
    print_html $m->plot ? $m->plot : "&nbsp;?";
    #print_html "</font>";
    print_html "</td></tr>";

print_html '<tr class="otherplaces"><td class="some">
<a href="http://movies.io/m/search?utf8=%E2%9C%93&q=', $m->title, '" class="moviesio"><span>Movies.io</span></a>
<a href="http://www.listal.com/search/movies/', $m->title, '" class="listal"><span>Listal</span></a>
<a href="http://www.jinni.com/movies/', $m->title, '" class="jinni"><span>Jinni</span></a>
<a href="http://www.imdb.com/title/tt', $m->id, '" class="imdb"><span>IMDb</span></a>
<a href="http://www.flixster.com/search/?search=', $m->title, '" class="flixster"><span>Flixster</span></a>
<a href="http://getglue.com/search?q=', $m->title, '" class="getglue"><span>GetGlue</span></a>
<a href="http://letterboxd.com/search/', $m->title, '" class="letterboxd"><span>Letterboxd</span></a>
</td></tr>
';
    print_html '<tr class="moviemeta"><td class="absoluted">';
    if (@tags) {
        print_html "<span class=tagss>Tags: <span class=MTAGS>", join(' ', @tags), "</span><br></span>";
    }

    print_html "Location: ";
    my $i = 0;
    my $nloc = scalar @location;
    my $dirtime = 0;
    for my $loc (sort by_alpha @location) {
        $i++;
        if ($nloc > 1) {
            print_html "<b>($i)</b> ";
        }
        my $dirent = get_dirent_location($loc);
#        if ($dirent->{guess}) {
#            print_html "<b>(GUESSED)</b> ";
#        }
        print_html format_html_path($loc);
        # print_html "dt: ", $all_dirs{$loc}->{mtime};
        if ($dirtime < $dirent->{mtime}) {
            $dirtime = $dirent->{mtime};
        }
    }
    # print_html "<br>dirtime: ";
    print_html "<span class=MDIRTIME>$dirtime</span>";
    if (@subsearch) {
        print_html "<br>Subtitles: ";
        format_links $m, 0, @subsearch;
    }
    if (@opt_links) {
        print_html "<br>Links: ";
        format_links $m, 1, @opt_links;
    }
    # print_html "<br><a href=../imdb_cache/imdb-",$m->id,".html>cache</a>";
    print_html "</font></td></tr>";

    print_html "</table><br>\n";
}

sub is_missing_file
{
    my ($dir, $fname) = @_;
    if ($opt_miss_match) {
        return 0 if ($all_dirs{$dir}->{file}{$fname}->{info}
                and !$all_dirs{$dir}->{file}{$fname}->{guess});
    } else {
        return 0 if ($all_dirs{$dir}->{file}{$fname}->{info});
    }
    for my $ign (@ignorelist) {
        if (match_path($dir, $fname, $ign)) {
            return 0;        
        }
    }
    return 1;
}

sub is_missing
{
    my $dir = shift;
    if ($opt_miss_match) {
        return 0 if ($all_dirs{$dir}->{info} and !$all_dirs{$dir}->{guess});
    } else {
        return 0 if ($all_dirs{$dir}->{info});
    }
    return 0 if (!$all_dirs{$dir}->{relevant});
    for my $ign (@ignorelist) {
        if (match_path(dirname($dir), basename($dir), $ign)) {
            return 0;        
        }
    }
    # if all video files have appropriate matches, don't report as missing
    my $n_movies = 0;
    for my $fname (keys %{$all_dirs{$dir}->{relevant}}) {
        if (match_ext($fname, @video_ext)) {
            $n_movies++;
            if (is_missing_file($dir, $fname)) { return 1; }
        }
    }
    if ($n_movies > 0) { return 0; }
    return 1;
}

sub count_missing
{
    my $nmiss = 0;
    for my $dir (keys %all_dirs) {
        next unless is_missing($dir);
        $nmiss++;
    }
    return $nmiss;
}

sub format_guess
{
    my ($dir, $fname) = @_;

    my $dirent = get_dirent($dir, $fname);

    print_html format_html_path("$dir/$fname");
    my ($title, $year) = path_to_guess($fname ? cut_ext($fname) : $dir);
    print_html "<br> Guessed title: ";
    print_html "<a href=\"", IMDB::Movie::get_url_find($title,$year), "\">";
    print_html "$title</a> (", $year?$year:"?", ")<br>";

    if ($dirent->{info} and $dirent->{guess}) {
        my $id = (keys %{$dirent->{id}})[0];
        my $movie = getmovie($id);
        print_html "Exact Match:";
        format_movie($movie, [ "$dir/$fname" ] );
        return 1; # exact match
    } else {
        my $nmatch = $dirent->{matches};
        if ($nmatch) {
            print_html "Matches: ", $nmatch;
            print_html "<br>First Match: ";
            my $id = $dirent->{matchlist}->[0]{id};
            my $movie = getmovie($id);
            format_movie($movie, [ "$dir/$fname" ] );
        } elsif ($nmatch eq undef) {
            print_html "Not Auto-Matching.<br><br>";
        } else {
            print_html "No Match.<br><br>";
        }
    }
}


sub report_missing
{
    my @sort_dirs = sort by_alpha keys %all_dirs;
    my $perf_match = 0;

    print_html "<br>Directories with missing info:<br>";
    print_html "<ul>";
    for (my $cur_dir=0; $cur_dir<scalar @sort_dirs; $cur_dir++) {
        my $dir = $sort_dirs[$cur_dir];
        next unless is_missing($dir);
        print_html "<li>[", $cur_dir + 1, "]";
        $perf_match += format_guess($dir);
        # filename guesses
        print_html "<ul>";
        my $fname;
        for $fname (keys %{$all_dirs{$dir}->{relevant}}) {
            next unless match_ext($fname, @video_ext);
            next unless is_missing_file($dir, $fname);
            print_html "<li>";
            $perf_match += format_guess($dir, $fname);
        }
        print_html "</ul>";
        # filename guesses
        print_html "<br><br>";
    }
    print_html "</ul>";
    print_html "<br>Total ", count_missing, " Directories with missing info<br>";
    if ($opt_miss_match) {
        print_html "<br>Exact matches: ", $perf_match, "<br>";
    }
    print_detail "Exact matches: $perf_match\n";
}

sub by_title {
    $pmlist->{$a}->{movie}->title  cmp  $pmlist->{$b}->{movie}->title;
}

sub by_rating {
    my $order = $pmlist->{$b}->{movie}->user_rating  <=>  $pmlist->{$a}->{movie}->user_rating;
    return $order ? $order : by_title;
}

sub by_runtime {
    my $order = $pmlist->{$a}->{movie}->runtime  <=>  $pmlist->{$b}->{movie}->runtime;
    return $order ? $order : by_title;
}

sub get_gfname {
    my $gfname = shift;
    return "" unless $gfname;
    return "" unless (scalar @group > 1 or ($opt_js and $opt_miss)); 
    return "" if ($group[0]->{title} eq $gfname);
    $gfname =~ s/[\W]/_/g; # replace non-alphanum with _
    $gfname = "_" . lc( $gfname ); # lo-case
    return $gfname;
}

sub page_head_group {
    my ($fadd, $gname, $this_gname, $gnm) = @_;
    if ($this_gname eq $gname) {
        print_html "<b>[$gname ($gnm)]</b> &nbsp;";
    } else {
        my $gfname = get_gfname($gname);
        print_html "<a href=$base_name$gfname$fadd.html>$gname ($gnm)</a> &nbsp;";
    }
}

sub page_head_jsort {
    my ($sname) = @_;
    print_html "<a id=\"SORT_", uc($sname), "\"",
                " href=javascript:sort_", lc($sname), "()>$sname</a> ";
}

sub page_head_jsort_user {
    my ($uid, $uname) = @_;
    print_html "<a id=\"SORT_UV", $uid , "\"",
                " href=javascript:sort_user('", $uid, "')>$uname</a> ";
}

sub page_head_sort {
    my ($fbase, $this_fadd, $add, $sname) = @_;
    if ($opt_js) {
        page_head_jsort($sname);
    } else {
        if ($this_fadd eq $add) {
            print_html "<b>[$sname]</b>";
        } else {
            print_html "<a href=$fbase$add.html>$sname</a>";
        }
    }
}

sub page_start
{
    my ($gname, $fadd) = @_;
    my $gfname = get_gfname($gname);
    my $fname = $base_path . $gfname . $fadd . ".html";

    open $F_HTML, ">", $fname  or  abort "Can't write $fname";
    print_note "Writing $fname\n";
    html_start;
    html_head("Leffakatalogi" . ($gname ? ": $gname" : ""));

    print_html
        '<form style="position: absolute; top: 2pt; right: 2pt;" name="ThemeForm">'.
        'Theme:'.
        '<select name="ThemeList" size="1" onChange="switchTheme(this.form)">';
    for my $tfile (glob "$prog_dir/lib/*.css") {
        my $theme;
        if ($tfile =~ /^.*[\/\\](.*)\.css$/) {
            $theme = $1;
        } else {
            next;
        }
        my $sel = ($theme eq $opt_theme);
        print_html '<option ' . ($sel?'selected ':'')
            . 'value="' . $theme . '">' . $theme . '</option>';
    }
    print_html '</select></form>';

    if (scalar @group > 1 or ($opt_js and $opt_miss)) { 
        print_html "<table class=missing><td>";
        print_html "<table cellpadding=0 cellspacing=0><tr>" if ($opt_group_table);
        for my $g (@group) {
            my $gnm = scalar keys %{$g->{mlist}};
            print_html "<td>" if ($opt_group_table);
            page_head_group $fadd, $g->{title}, $gname, $gnm;
            if ($g->{separate}) {
                if ($opt_group_table) {
                    print_html "<tr>";
                } else {
                    print_html "&nbsp;&nbsp;<br>";
                }
            }
        }
        if ($opt_miss) {
            print_html "<td>" if ($opt_group_table);
            page_head_group "", "Missing Info", $gname, count_missing;
        }
        print_html "</table>" if ($opt_group_table);
        print_html "</table>";
    }

    if ($opt_miss and $gname eq "Tietoja ei löytynyt") {
        # no sort menu
    } else {
        my $fbase = "$base_name$gfname";
        print_html '<div class="sort-options">';
        page_head_sort $fbase, $fadd, "", "Title";
        page_head_sort $fbase, $fadd, "-rating", "Rating";
        page_head_sort $fbase, $fadd, "-runtime", "Runtime";
        if ($opt_js) {
            page_head_sort $fbase, $fadd, "-year", "Year";
            print_html "<small>";
            #page_head_sort $fbase, $fadd, "-dirtime", "DirTime";
            if (@opt_user) {
                print_html "User Votes: ";
                my $uid;
                for my $uv (@user_vote) {
                    $uid++;
                    page_head_jsort_user $uid, $uv->{'name'};
                }
            }
            print_html "</small>";
        } else {
            page_head_sort $fbase, $fadd, "-genre", "Genre";
            if ($opt_miss and scalar @group == 1) {
                page_head_sort $fbase, $fadd, "-missinfo", "Missing Info";
            }
        }
        print_html "</div>";

    }
}

sub page_end
{
    print_html "</div></body></html>";
    close $F_HTML;
}

sub page_footer
{
    if (scalar keys %{$pmlist} == 0) {
        print_html "<br>No Movies Found!<br>";
    } elsif (scalar @group < 2 and !$opt_js) {
        print_html "<br>Total: ", scalar keys %{$pmlist}, " Movies<br>";
    }
    if (@user_vote) {
        print_html "<small>User votes: ";
        for my $uv (@user_vote) {
            my $votes = scalar keys %{$uv->{'vote'}};
            if ($uv->{'name'} ne $uv->{'user'}) {
                print_html $uv->{'name'}, "=";
            }
            print_html "<a href=\"", $uv->{'url'}, "\">", $uv->{'user'}, "</a>",
                       " (", $uv->{'count'}, "/$votes votes) &nbsp;";
            $uv->{'count'} = 0;
        }
        print_html "</small>";
    }
}

sub get_all_genres
{
    my %genres;
    for my $id (keys %{$pmlist}) {
        # if a movie has no genre add "unknown" to list
        if (!@{$pmlist->{$id}->{movie}->genres}) {
            push @{$pmlist->{$id}->{movie}->genres}, "unknown";
        }
        for my $g (@{$pmlist->{$id}->{movie}->genres}) {
            $genres{$g} = 1;
        }
    }
    return keys %genres;
}

sub get_max_year
{
    my $maxyear = 2000;
    for my $m (values %movie) {
        if ($m->year > $maxyear) { $maxyear = $m->year; }
    }
    return $maxyear;
}

sub get_max_runtime
{
    my $maxrun = 200;
    for my $m (values %movie) {
        if ($m->runtime > $maxrun) { $maxrun = $m->runtime; }
    }
    return $maxrun;
}

sub by_tag
{
    my $order = $gbl_tags{$a}{order} <=> $gbl_tags{$b}{order};
    return $order ? $order : by_alpha;
}

sub page_filter
{
    my @genres = sort by_alpha get_all_genres;
    my $maxyear = get_max_year();
    my $maxrunt = get_max_runtime();
    my $i = 0;
    print_html "<span id=FILTER_HEAD><small>";
    print_html "<i id=STATUS>", scalar keys %{$pmlist},
               " movies</i> ";
    print_html "&nbsp; <a href=javascript:filter_reset()>reset</a>";
    print_html "&nbsp; <a id=SHOW_FILTER1 href=javascript:show_filter(1)>",
               "show tags</a>";
    print_html "&nbsp; <a id=SHOW_FILTER2 href=javascript:show_filter(2)>",
               "show genre</a>";
    print_html "&nbsp; <a id=SHOW_FILTER3 href=javascript:show_filter(3)>",
               "more</a>";
    print_html "</small></span>";

    print_html "<form id=FORM_FILTER style='display:inline'",
               " onsubmit=do_filter();return(false)>";

    print_html "<table id=FILTER_TABLE cellspacing=3 cellpadding=0 bgcolor=silver>";
    print_html "<tr valign=top>";

    print_html "<td id=HIDE_FILTER1>";
    print_html "<table id=TAG_TABLE cellspacing=0 cellpadding=0>";
    print_html "<tr valign=top>";
    print_html "<td><br><small>";
    print_html "<a href=javascript:tag_all()>all</a>&nbsp;&nbsp;<br>";
    print_html "<a href=javascript:hide_filter(1)>hide</a>&nbsp;&nbsp;<br>";
    print_html "</small></td>";
    print_html "<td><small>";
    print_html "<table cellspacing=0 cellpadding=0>";
    my @tags = sort by_tag keys %{$pgroup->{tag}};
    my $tag_count = 0;
    for my $tag (@tags) {
        if ($gbl_tags{$tag}{state} eq "hide") { next; }
        my $state = $gbl_tags{$tag}{state} ? $gbl_tags{$tag}{state} : "all";
        my $tid = "TAG_" . uc($tag);
        print_html "<tr>";
        print_html "<td><input type=radio id=$tid"."_ALL name=$tid value=all",
                   ($state eq "all" ? " checked=checked" : ""), " onclick=do_filter()>",
                   "<span class=HOVER_ULN onclick=tag_set(\'$tid\','ALL')>all</span>&nbsp;";
        print_html "<td><input type=radio id=$tid"."_NOT name=$tid value=not",
                   ($state eq "not" ? " checked=checked" : ""), " onclick=do_filter()>",
                   "<span class=HOVER_ULN onclick=tag_set(\'$tid\','NOT')>not</span>&nbsp;";
        print_html "<td><input type=radio id=$tid"."_SET name=$tid value=set",
                   ($state eq "set" ? " checked=checked" : ""), " onclick=do_filter()>",
                   "<span class=HOVER_ULN onclick=tag_set(\'$tid\','SET')>$tag (",
                   $pgroup->{tag}{$tag}, ")</span>&nbsp;";
        print_html "</tr>";
        $tag_count++;
    }
    print_html "</table>";
    print_html "</small></td>";
    print_html "<td style='width:1em'></td>";
    print_html "</tr></table></td>";


    print_html "<td id=HIDE_FILTER2>";
    print_html "<table id=GENRE_TABLE cellspacing=0 cellpadding=0>";
    print_html "<tr valign=top>";
    print_html "<td class=filtergenretd><div class=filtergenreoptions><small>";
    print_html "<a href=javascript:genre_all()>all</a>&nbsp;&nbsp;<br>";
    print_html "<a href=javascript:genre_none()>none</a>&nbsp;&nbsp;<br>";
    print_html "<a href=javascript:hide_filter(2) style=\"padding:0 !important;\">hide</a>&nbsp;&nbsp;<br>";
    print_html "</small></div></td>";
    print_html "<td><small>";
    my $g_rows = 5;
    if ($tag_count > $g_rows) { $g_rows = $tag_count; }
    for my $g (@genres) {
        my $gid = "G_" . uc($g);
        print_html "<div class=filtergenre><input type=checkbox id=$gid checked=checked onclick=do_filter()>",
                   "<span class=HOVER_ULN onclick=genre_one(\'$gid\')>$g</span>&nbsp;&nbsp;&nbsp;<br></div>";
        $i++;
        if ($i >= $g_rows) {
            print_html "</small></td><td><small>";
            $i = 0;
        }
    }
    print_html "</small></td>";
    print_html "<td style='width:1em'></td>";
    print_html "</tr></table></td>";

    print_html "<td id=HIDE_FILTER3>";
    print_html "<table id=RANGE_TABLE cellspacing=0 cellpadding=0>";

    print_html "<tr class=rangetr><td class=newsort>Year: <td>";
    print_html "<input type=text id=YMIN value=0 maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()> - ";
    print_html "<input type=text id=YMAX value=$maxyear maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()></tr>";

    print_html "<tr class=rangetr><td class=newsort>Rating: <td>";
    print_html "<input type=text id=RMIN value=0 maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()> - ";
    print_html "<input type=text id=RMAX value=10 maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()></tr>";

    print_html "<tr class=rangetr><td class=newsort>Duration: <td>";
    print_html "<input type=text id=TMIN value=0 maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()> - ";
    print_html "<input type=text id=TMAX value=$maxrunt maxlength=5 size=2",
               " onkeyup=numbersOnly(this) onchange=do_filter()></tr>";
    print_html "<tr><td colspan=2><small>";
    #print_html " <input type=button value=Filter style='height: 1.6em' onclick=do_filter()>";
    print_html "&nbsp; <a href=javascript:hide_filter(3)>hide</a>";
    print_html "</small></tr></table></td>";

    print_html "</tr></table>";
    print_html "</form>&nbsp;&nbsp;<br>";

    # init filter
    print_html "<script type=\"text/javascript\">init_filter();</script>";
}

sub print_page
{
    my ($gname, $fadd, $sort_by) = @_;

    page_start($gname, $fadd);

    if ($opt_js) {
        page_filter;
    }

    print_html '<table id="MTABLE" cellspacing="0" cellpadding="0">';
    for my $id (sort $sort_by keys %{$pmlist}) {
        print_html "<tr class=movieitself><td class=moviecontent>";
        format_movie_id($id);
        print_html "</td></tr>";
    }
    print_html "</table>";

    page_footer;
    page_end;
}

sub print_page_genre
{
    my ($gname) = @_;

    page_start($gname, "-genre");

    my %genres;
    my @glist;
    my $g;
    # build a genre list from all movies
    for my $id (keys %{$pmlist}) {
        for $g (@{$pmlist->{$id}->{movie}->genres}) {
            $genres{$g}{$id} = $pmlist->{$id};
        }
    }

    if (!%{$pmlist}) {
        print_html "<br><br><ul><i>* No Movies *</i></ul><br><br>";
    } else {
        print_html "Genre: <ul>";
        @glist = sort by_alpha keys %genres;
        for $g (@glist) {
            my $ng = scalar keys %{$genres{$g}};
            print_html "<li><a href=#$g>$g</a> ($ng)";
        }
        print_html "</ul><br>";

        for $g (@glist) {
            print_html "<a name=$g><br><hr><h2><center>$g</center></h2><hr></a><br>";
            for my $id (sort by_rating keys %{$genres{$g}}) {
                format_movie_id($id);
            }
        }
    }

    page_footer;
    page_end;
}

sub print_page_miss
{
    my ($gname, $fadd) = @_;
    page_start($gname, $fadd);
    report_missing;
    page_end;
}

sub xml_quote
{
    my $text = shift;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/'/&apos;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

sub format_movie_xml
{
    my ($m, @location) = @_;

    my $img;
    if ($m->img) {
        my $img_file = img_name($m->id);
        $img = $image_dir ."/". $img_file;
        if ( ! -e $image_cache ."/". $img_file ) { $img = $m->img; }
    }
    print_html "  <movie>";
    print_html "    <image>$img</image>";
    print_html "    <id>", $m->id, "</id>";
    print_html "    <title>", xml_quote($m->title), "</title>";
    print_html "    <year>", $m->year, "</year>";
    print_html "    <type>", $m->type, "</type>";
    print_html "    <rating>", $m->user_rating, "</rating>";
    print_html "    <runtime>", $m->runtime, "</runtime>";
    print_html "    <genre>", join(',',@{$m->genres}), "</genre>";
    print_html "    <plot>", xml_quote($m->plot), "</plot>";
    print_html "    <location>", xml_quote(join(',',@location)), "</location>";
    print_html "  </movie>";
}

sub print_xml
{
    my ($gname) = @_;
    my $gfname = get_gfname($gname);
    my $fname = $base_path . $gfname . ".xml";

    open $F_HTML, ">", $fname  or  abort "Can't write $fname";
    print_note "Writing $fname\n";

    print_html '<?xml version="1.0" ?>';
    print_html '<?xml-stylesheet type="text/xsl" href="movie.xsl"?>';
    print_html "<movielist>";
    for my $id (sort by_title keys %{$pmlist}) {
        format_movie_xml($pmlist->{$id}->{movie}, keys %{$pmlist->{$id}->{location}});
    }
    print_html "</movielist>";

    close $F_HTML;
}

sub copy_lib
{
    my $name = shift;
    my $src = "$prog_dir/lib/$name";
    my $dest = $base_dir . $name;
    print_note "Writing $dest\n";
    copy($src, $dest) or abort "Copy $src -> $dest Failed!";
}

sub print_report
{
    # if no missing, disable opt_miss
    if (count_missing == 0) { $opt_miss = 0; }
    # if no title, assign a default one
    if (!$group[0]->{title} and $opt_miss) {
        $group[0]->{title} = "Movies";
    }

    print_info "Generating catalog...\n";
    for my $g (@group) {
        my $gname = $g->{title};
        $pgroup = $g; # set current group
        $pmlist = \%{$g->{mlist}};
        print_page $gname, "", \&by_title;
        if (!$opt_js) {
            print_page $gname, "-rating", \&by_rating;
            print_page $gname, "-runtime", \&by_runtime;
            print_page_genre $gname;
            if ($opt_miss and scalar @group == 1) {
                print_page_miss $gname, "-missinfo";
            }
        }
        if ($opt_xml) {
            print_xml $gname;
        }
    }
    if ($opt_miss and (scalar @group > 1 or $opt_js)) {
        print_page_miss "Missing Info", "";
    }
    if ($opt_js) {
        copy_lib $jsname;
        # *.png
        for my $f (glob "$prog_dir/lib/*.png") {
            copy_lib basename($f);
        }
        # *.css
        my $theme_found = 0;
        for my $tfile (glob "$prog_dir/lib/*.css") {
            my $theme = basename($tfile);
            if ($theme eq "$opt_theme.css") { $theme_found = 1; }
            copy_lib $theme;
        }
        if (!$theme_found) {
            print_error "Theme not found: $opt_theme";
        }
    }
}


###############################

### Interactive

sub path_to_guess
{
    my $path = shift;
    my $name = basename($path);
    if (uc($name) eq "VIDEO_TS" or $name =~ /^cd[1-4]$/i) {
        # if VIDEO_TS or CD1/2 get parent dir
        $name = basename(dirname($path));
    }
    my $title = $name;
    my $year;
    my $type;
    my $ccount;
    # search for year
    # (get last 4 digit num and preceding text, strip the rest)
    if ($name =~ /^(.+)(\b\d{4}\b)/) {
        $year = $2;
        my $cur_year = 1900 + ((localtime)[5]);
        if ($year >= 1920 and $year <= $cur_year + 2) {
            $title = $1;
        } else {
            $year = 0;
        }
    }
    #print_debug "YEAR: $year : $title\n";
    #remove codec info
    $title =~ s/_/ /g; # treat _ as space (\w includes _)
    for my $c (@codec, @series_tag) {
        if ($title =~ s/\W$c\b.*$//i) {
            $ccount++;
        }
    }
    # $title =~ s/[^\w']/ /g; # replace non alphanum to space, keep '
    $title =~ s/[^\w'()]/ /g; # replace non alphanum to space, keep '()
    $title =~ s/\(+$//;   # strip trailing ( - remains of (year)
    $title =~ s/^ +//;   # strip leading space
    $title =~ s/ +$//;   # strip trailing space
    $title =~ s/ +/ /g;   # strip duplicate space
    # check if series
    for my $x (@series_tag) {
        if ($name =~ /\W$x\b/i) {
            $type = "series";
            last;
        }
    }
    print_debug "path_to_guess: '$title' ($year) [$type] <$ccount>\n";

    return ($title, $year, $type, $ccount);
}

sub get_guess_list
{
    my @guess;
    my %seen; # make unique
    for my $file (@_) {
        my ($t,$y) = path_to_guess($file);
        next unless ($t);
        my $sid = lc("$t y $y");
        next if ($seen{$sid}++);
        push @guess, { title => $t, year => $y };
    }
    return @guess;
}

sub list_file
{
    my ($dir, $f) = @_;
    my $fn = "$dir/$f";
    if (-d $fn) {
        print "           $f/\n";
    } elsif (-f $fn) {
        my $size = (-s _) / 1024 / 1024;
        printf "  %6.1fM  %s\n", $size, $f;
    } else {
        print "           $f\n";
    }
}

sub list_files
{
    my $dir = shift;
    my @flist;
    opendir(my $dh, $dir) or print_error("opendir $dir") and return;
    for my $f (sort by_alpha readdir($dh)) {
        next if ($f eq "." or $f eq "..");
        my $fn = "$dir/$f";
        if (-d $fn) {
            list_file $dir, $f;
        } else { push @flist, $f; }
    }
    for my $f (@flist) {
        list_file $dir, $f;
    }
    print "\n";
    close $dh;
}


sub list_relevant
{
    my ($dir, @files) = @_;
    print_info "Relevant files:\n";
    for my $f (sort by_alpha @files) {
        #print_info "  $f\n";
        list_file $dir, $f;
    }
    print_info "\n";
}

sub print_dir
{
    my ($all, $i, $dir) = @_;
    my $dtag;
    if ($all_dirs{$dir}->{info}) {
        next if (!$all);
        if ($all_dirs{$dir}->{guess}) {
            $dtag = "g";
        } else {
            $dtag = "*";
        }
    } elsif ($all_dirs{$dir}->{relevant}) {
        $dtag = "-";
    } else {
        next if ($all < 2);
        $dtag = " ";
    }
    print_info "  $dtag [$i] $dir\n";
}

sub list_dirs
{
    my $all = shift;
    my @dirs = @_;
    if ($all) { print_info "\nAll Directories:\n\n"; }
    else { print_info "\nDirectories with missing info:\n\n"; }
    my $i;
    for my $dir (@dirs) {
        $i++;
        print_dir $all, $i, $dir;
    }
    print_info "\n";
}

sub get_subdirs
{
    my ($dir, @dirs) = @_;
    my @subdirs;
    for my $d (@dirs) {
        if (index($d, "$dir/") == 0) {
            my $subdir = substr($d, length "$dir/");
            if (index($subdir, "/") < 0) {
                # found subdir
                push @subdirs, $subdir;
            }
        }
    }
    return @subdirs;
}

sub list_subdirs
{
    my ($dir, @dirs) = @_;
    my @subdirs = get_subdirs($dir, @dirs);
    if (scalar @subdirs) {
        print_info "\nSub-Directories:\n";
    } else {
        print_info "No Sub-Directories.";
    }
    for my $sd (@subdirs) {
        my $d = "$dir/$sd";
        my $i = $all_dirs{$d}->{idx};
        print_dir 2, $i+1, $sd;
    }
    print_info "\n";
}

sub find_dir
{
    my ($dir, $arg, @dirs) = @_;
    if ($arg eq "/") {
        return 0;
    } elsif ($arg eq ".") {
        return $all_dirs{$dir}->{idx};
    } elsif ($arg eq "..") {
        return -1 if (rindex($dir, "/") < 0);
        $arg = substr($dir, 0, rindex($dir, "/"));
    } else {
        # search relative dir
        my $sdir = "$dir/$arg";
        if ($all_dirs{$sdir}) {
            return $all_dirs{$sdir}->{idx};
        }
    }
    # search absolute dir
    if ($all_dirs{$arg}) {
        return $all_dirs{$arg}->{idx};
    }
    return -1;
}

sub run_cmd
{
    my ($dir, $cmd) = @_;
    if (!$cmd) {
        print_error "Missing CMD";
        return;
    }
    my $cwd = getcwd;
    # opendir $cwd, ".";
    chdir $dir;
    print_info "Running '$cmd' in $dir\n\n";
    system($cmd);
    chdir $cwd;
    # system("pwd");
    print_info "\n";
}

sub unique_matches {
    my %seen;
    # fix first match type
    if ($_[0] and $_[0]->{id} and !$_[0]->{type} and ($_[0]->{id} eq $_[1]->{id})) {
        $_[0]->{type} = $_[1]->{type};
    }
    grep(!$seen{$_->{id}}++, @_);
}

sub get_input
{
    my $in = <STDIN>;
    print_log "INPUT: $in";
    if ($in eq undef) { print_info "<eof>\nexit\n"; last; } # eof
    chomp $in;
    if ($in eq "q" or $in eq "quit" or $in eq "exit") {
        exit;
    }
    return $in;
}

sub do_search
{
    my ($dir, $title, $year) = @_;
    print_info "Searching for '$title' ($year)...";
    # my $mfound = IMDB::Movie->new($title);
    my $mfound = IMDB::Movie->new($title, $year);
    print_info "\n";
    if ($mfound eq undef) {
        print_info "No match found for '$title'\n";
    } else {
        my @matches = unique_matches(@{$mfound->matches});
        if (!@matches) {
            push @matches, {id => $mfound->id, title => $mfound->title, year => $mfound->year};
        }
        sub match_string {
            my $ma = shift;
            return "[".$ma->{id}."]  ".$ma->{title}." (", $ma->{year}, ") ".$ma->{type};
        }
        my $i;
        for my $ma (@matches) {
            $i++;
            print_info "  $i) ", match_string($ma);
            print_info "[Exact match]" if $mfound->{direct_hit};
            print_info "\n";
            # print_info "     ", IMDB::Movie::get_url_id($ma->{id}), "\n";
            last if ($i >= 20);
        }
        my $num_m = scalar @matches;
        $num_m = $num_m > 20 ? 20 : $num_m;
        print_info "Select [1-$num_m] or <enter> to return\n";
        print_info "Match: ";
        my $sel = get_input;
        if ($sel >=1 and $sel <= $num_m) {
            my $ma = $matches[$sel-1];
            print_info "Selected match:\n";
            print_info "  $sel) ", match_string($ma), "\n";
            print_info "Getting full info .."; 
            my $m = getmovie($ma->{id});
            if (!$m) {
                print_error "Getting full info for [", $ma->{id}, "]";
            } else {
                print_info " OK.\n";
                save_movie($dir, $m);
                dir_assign_movie($dir, $m);
                print_info "Done.\n";
            }
            print_info "[enter to continue]";
            get_input;
        }
    }
    print_info "\n";
}


sub print_ihelp
{
    print_info << "IHELP";

Interactive help:

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
ignoredir       -  Add dir to ignore.txt
!CMD            -  Run command CMD in dir
r               -  Recreate Report
? / h / help    -  Print Help
q / quit        -  Quit

IHELP
}

sub interactive
{
    # sort
    my @sort_dirs = sort by_alpha keys %all_dirs;
    for (my $i=0; $i<scalar @sort_dirs; $i++) {
        # index
        $all_dirs{$sort_dirs[$i]}->{idx} = $i;
    }

    my $cur_dir = 0;
    my $nmiss = count_missing;
    print_info "Directories with missing info: ",
               $nmiss, " / ", scalar @sort_dirs, "\n\n";
    print_info "\n===== Interactive mode =====\n";

    my $dir;
    my @files;
    my @guess;
    my $num_guess;

    my $s_nextmiss = 0;
    my $s_chdir = 1;
    my $s_info = 2;
    my $s_cmd = 3;
    my $s_search = 4;
    my $state = $nmiss ? $s_nextmiss : $s_chdir;

    while (1) {

        if ($state <= $s_nextmiss) {
            # NEXT_MISS:
            while ($cur_dir < scalar @sort_dirs -1) {
                last if (is_missing($sort_dirs[$cur_dir]));
                $cur_dir++;
            }
        }

        if ($state <= $s_chdir) {
            # CHDIR:
            $dir = $sort_dirs[$cur_dir];
            @files = ();
            if ($all_dirs{$dir}->{relevant}) {
                @files = keys %{$all_dirs{$dir}->{relevant}};
            }
            @guess = get_guess_list($dir, cut_ext_l(@files));
            # show max 9 guesses
            $num_guess = scalar @guess > 9 ? 9 : scalar @guess;
        }

        if ($state <= $s_info) {
            # INFO:
            print_info "\n\nDirectory:\n\n";
            print_dir 2, $cur_dir + 1, $dir;
            print_info "\nMovies:";
            if ($all_dirs{$dir}->{id}) {
                print_info "\n";
                for my $id (keys %{$all_dirs{$dir}->{id}}) {
                    print_info "  * [$id] ", $movie{$id}->title,
                    " (", $movie{$id}->year, ")\n";
                }
            } else {
                print_info " *Missing Info*\n";
            }
            print_info "\nGuessed titles:\n";
            for my $n (1 .. $num_guess) {
                print_info "  $n) ", $guess[$n-1]->{title},
                " (", $guess[$n-1]->{year}, ")\n";
            }
            print_info "\nSelect [1-",$num_guess,"] or enter title or imdb url\n";
        }

        # CMD:
        $state = $s_cmd;
        print_info "[enter=next missing  q=quit  ?=help]\n";
        print_info "> ";
        my $cmd = get_input;

        if ($cmd eq undef) {  # enter
            if ($cur_dir == scalar @sort_dirs -1) {
                print_info "Last Directory! [", $cur_dir+1, "]\n";
            } else {
                $cur_dir++;
                $state = $s_nextmiss;
            }
            next;

        } elsif ($cmd eq "?" or $cmd eq "h" or $cmd eq "help") {
            print_ihelp;

        } elsif ($cmd eq ".") {
            $state = $s_info;
            next;

        } elsif ($cmd eq "pwd") {
            print_dir 2, $cur_dir + 1, $dir;

        } elsif ($cmd eq "l") {
            list_relevant $dir, @files;

        } elsif ($cmd eq "ll" or $cmd eq "ls") {
            list_files $dir;

        } elsif ($cmd eq "d") {
            list_dirs 0, @sort_dirs;

        } elsif ($cmd eq "dd") {
            list_dirs 2, @sort_dirs;

        } elsif ($cmd eq "dir") {
            list_subdirs $dir, @sort_dirs;

        } elsif ($cmd =~ /^c +(\d+)$/) {
            if ($1 >=1 and $1 <= scalar @sort_dirs) {
                $cur_dir = $1 - 1;
                $state = $s_nextmiss;
                next;
            }

        } elsif ($cmd =~ /^cd +(.+) *$/) {
            my $arg = $1;
            if (($arg =~ /^\d+$/) and $arg >=1 and $arg <= scalar @sort_dirs) {
                $cur_dir = $arg - 1;
                $state = $s_chdir;
                next;
            } else {
                my $new_dir = find_dir($dir, $arg, @sort_dirs);
                if ($new_dir >= 0 and $new_dir <= scalar @sort_dirs) {
                    $cur_dir = $new_dir;
                    $state = $s_chdir;
                    next;
                }
                print_info "Directory '", $arg, "' Not found!\n";
            }

        } elsif ($cmd eq "n") {
            if ($cur_dir < scalar @sort_dirs -1) {
                $cur_dir++;
                $state = $s_chdir;
                next;
            } else {
                print_info "Last Directory! [", $cur_dir+1, "]\n";
            }

        } elsif ($cmd eq "p") {
            if ($cur_dir > 0) {
                $cur_dir--;
                $state = $s_chdir;
                next;
            } else {
                print_info "First Directory! [", $cur_dir+1, "]\n";
            }

        } elsif ($cmd eq "ignoredir") {
            my $F_IGN;
            my $fign = "$prog_dir/ignore.txt";
            if (!open($F_IGN, ">>", $fign)) {
                print_error "open $fign";
            } else {
                print $F_IGN "\n-ignore $dir\n";
                close $F_IGN;
                print_info "Dir added to $fign.\n(use -c ignore.txt)\n\n";
            }

        } elsif ($cmd eq "r") {
            print_report;
            print_info "\n";

        } elsif ($cmd =~ /^!(.*)$/) {
            my $run = $1;
            run_cmd($dir, $run);

        } elsif ($cmd =~ /^\d{7}$/) {
            # search by ID            
            $state = $s_search;

        } elsif ($cmd >= 1 and $cmd <= $num_guess) {
            do_search($dir, $guess[$cmd - 1]->{title}, $guess[$cmd - 1]->{year});
            $state = $s_info;
            next;

        } elsif ($cmd =~ /^s +(.+)$/) {
            $cmd = $1;
            $state = $s_search;

        } elsif (length $cmd >3) {
            $state = $s_search;

        } else {
            print_info "Unknown cmd: '$cmd'\n";
        }

        if ($state == $s_search) {
            # SEARCH:
            my $title = $cmd;
            my $year;
            if ($title =~ /^(.+) \((\d{4})\)$/) {
                $title = $1;
                $year = $2;
            } elsif ($title =~ /imdb.com\/title\/tt(\d{7})/i) {
                $title = $1;
            }
            do_search($dir, $title, $year);
            $state = $s_info;
            next;
        }

    }
}


###############################

### Options


sub required_arg {
    my ($opt, $arg) = @_;
    if (!defined($arg)) { abort "Missing arg for $opt"; }
    return 1;
}

sub set_opt
{
    my ($opt, $arg) = @_;
    my $arg_used = 0;

    print_log("OPT: '$opt' ($arg)");

    if ($opt eq "-v" or $opt eq "-verbose") {
        $verbose++;

    } elsif ($opt eq "-q" or $opt eq "-quiet") {
        $verbose = 0;

    } elsif ($opt eq "-i" or $opt eq "-interactive") {
        $opt_i = 1;

    } elsif ($opt eq "-o" or $opt eq "-out") {
        $arg_used = required_arg($opt, $arg);
        $base_path = $arg;

    } elsif ($opt eq "-t" or $opt eq "-title") {
        $arg_used = required_arg($opt, $arg);
        if ($group[$ngroup]->{title}) {
            $ngroup++;
        }
        $group[$ngroup]->{title} = $arg;

    } elsif ($opt eq "-g" or $opt eq "-group") {
        $group[$ngroup]->{separate} = 1

    } elsif ($opt eq "-gs" or $opt eq "-gskip") {
        $arg_used = required_arg($opt, $arg);
        push @{$group[$ngroup]->{skiplist}}, $arg;

    } elsif ($opt eq "-gx" or $opt eq "-gregex") {
        $arg_used = required_arg($opt, $arg);
        push @{$group[$ngroup]->{rxskiplist}}, $arg;

    } elsif ($opt eq "-ns" or $opt eq "-noskip") {
        @skiplist = (); # clear skip list
        @rxskiplist = (); # clear skip list

    } elsif ($opt eq "-s" or $opt eq "-skip") {
        $arg_used = required_arg($opt, $arg);
        push @skiplist, $arg;

    } elsif ($opt eq "-x" or $opt eq "-regex") {
        $arg_used = required_arg($opt, $arg);
        push @rxskiplist, $arg;

    } elsif ($opt eq "-ignore") { # short? -e?
        $arg_used = required_arg($opt, $arg);
        push @ignorelist, $arg;

    } elsif ($opt eq "-a" or $opt eq "-automatch") {
        $opt_auto = 1;

    } elsif ($opt eq "-na" or $opt eq "-noautomatch") {
        $opt_auto = 0;

    } elsif ($opt eq "-m" or $opt eq "-missing") {
        $opt_miss = 1;

    } elsif ($opt eq "-nm" or $opt eq "-nomissing") {
        $opt_miss = 0;

    } elsif ($opt eq "-mm" or $opt eq "-missmatch") {
        $opt_miss_match = 1;

    } elsif ($opt eq "-mf" or $opt eq "-matchfirst") {
        $opt_match_first = 1;

    } elsif ($opt eq "-my" or $opt eq "-matchyear") {
        $opt_match_year = 1;

    } elsif ($opt eq "-mfn" or $opt eq "-matchfilename") {
        $opt_match_fname = 1;

    } elsif ($opt eq "-nfn" or $opt eq "-nomatchfilename") {
        $opt_match_fname = 0;

    } elsif ($opt eq "-as" or $opt eq "-autosave") {
        $opt_auto_save = 1;

    } elsif ($opt eq "-c" or $opt eq "-config") {
        $arg_used = required_arg($opt, $arg);
        parse_cfg($arg);

    } elsif ($opt eq "-subs") {
        $arg_used = required_arg($opt, $arg);
        push @subsearch, $arg;

    } elsif ($opt eq "-nosubs") {
        @subsearch = ();

    } elsif ($opt eq "-link") {
        $arg_used = required_arg($opt, $arg);
        push @opt_links, $arg;

    } elsif ($opt eq "-nolink") {
        @opt_links = ();

    } elsif ($opt eq "-js") {
        $opt_js = 1;

    } elsif ($opt eq "-nojs") {
        $opt_js = 0;

    } elsif ($opt eq "-xml") {
        $opt_xml = 1;

    } elsif ($opt eq "-user") {
        $arg_used = required_arg($opt, $arg);
        push @opt_user, $arg;

    } elsif ($opt eq "-ext") {
        $arg_used = required_arg($opt, $arg);
        $arg =~ s/^\.//; # strip optional leading .
        push @media_ext, $arg;
        push @video_ext, $arg;

    } elsif ($opt eq "-tag") {
        $arg_used = required_arg($opt, $arg);
        my ($name,$pattern) = split('=', $arg, 2);
        if ($name =~ /[\s,]/) { abort "Invalid tag name: '$name'"; }
        my $plus = ($name =~ s/\+$//);
        if (!$plus) { @{$gbl_tags{$name}{pattern}} = (); }
        push @{$gbl_tags{$name}{pattern}}, split(',', $pattern);
        if (!$plus) { $gbl_tags{$name}{order} = scalar keys %gbl_tags; }

    } elsif ($opt eq "-tagorder") {
        $arg_used = required_arg($opt, $arg);
        my $count = -100;
        for my $t (split(',', $arg)) {
            $gbl_tags{$t}{order} = $count++;
        }

    } elsif ($opt eq "-tagstate") {
        $arg_used = required_arg($opt, $arg);
        my ($name,$val) = split('=', $arg, 2);
        if (! ($val =~ /^(all|not|set|hide)$/i)) { abort "Invalid tag state: $val"; }
        $gbl_tags{$name}{state} = lc($val);

    } elsif ($opt eq "-aka") {
        $opt_aka = 1;

    } elsif ($opt eq "-noaka") {
        $opt_aka = 0;

    } elsif ($opt eq "-cachedays") {
        $arg_used = required_arg($opt, $arg);
        $max_cache_days = $arg;

    } elsif ($opt eq "-theme") {
        $arg_used = required_arg($opt, $arg);
        $opt_theme = $arg;

    } elsif ($opt eq "-origtitle") {
        $opt_otitle = 1;

    } elsif ($opt eq "-deftitle") {
        $opt_otitle = 0;

    } elsif ($opt =~ /^-/) {
        abort "Unknown option: $opt";

    } else {
        $ndirs++;
        push @{$group[$ngroup]->{dirs}}, normal_path($opt);
        print_log("DIR: '$opt'");
    }
    return $arg_used;
}

my %cfg_check;

sub parse_cfg
{
    my $cfg_name = shift;
    if ($cfg_check{$cfg_name}++) {
        print_error "Recursive config: $cfg_name";
        exit_cfg;
    }
    my $F_CFG;
    my ($opt, $arg);
    if (!open $F_CFG, "<", $cfg_name) {
        print_error "open config: $cfg_name";
        exit_cfg;
    }
    while (<$F_CFG>) {
        chomp;   # strip newline
        s/\r$//; # strip carriage return
        s/^ *//; # strip leading space
        s/ *$//; # strip trailing space
        if (/^#/) { next; } # skip comment
        if (!$_) { next; }  # skip empty line
        print_log "CFG: '$_'";
        if (/^-/) {
            ($opt, $arg) = split / /, $_, 2;
        } else {
            $opt = $_;
            $arg = "";
        }
        set_opt($opt, $arg);
    }
    $cfg_check{$cfg_name}--;
}

sub version
{
    print_info "$progname $progver\n";
    print_level 2, "IMDB::Movie ", $IMDB::Movie::VERSION, "\n";
    print_info "$copyright\n";
}

sub usage
{
    my $long = shift;
    version;
    print_info << "USAGE";
Usage: perl $progbin [OPTIONS] [DIRECTORY ...]
  Options:
    -h|-help|-ihelp         Help (short|long|interactive)
    -V|-version             Version
    -v/q|-verbose/quiet     Verbose/Quiet output
    -c|-config <CFGFILE>    Load configuration
    -i|-interactive         Interactive mode
    -o|-out <FILENAME>      Output path base name
    -t|-title <TITLE>       Set Title (multiple to define groups)
    -g|-group               Group separator
    -s|-skip <NAME>         Skip file or dir (recursive) 
    -ignore <DIR>           Ignore dir with missing info (not recursive)
    -user VOTES_URL         Add user's votes from imdb user's vote history url
    -subs URL               Add subtitle search site
    -link URL               Add a custom link
    -tag NAME=PATTERN       Add a tag NAME if path matches PATTERN
    -ext EXT                Add a file extension of recognized media files
    DIRECTORY               Directory to scan
USAGE

    if (!$long) {
        print_info "    (Use -help for More Options)\n";
    } else {
        print_info << "USAGE_LONG";

  More Options:
    -tagorder TAGLIST       Specify tag order: TAG1,TAG2,TAG3,...
    -tagstate NAME=VAL      Specify default tag state: all, not, set, hide
    -x|-regex <EXPR>        Skip using regular expressions
    -ns|-noskip             Clear preset skip lists
    -gs|-gskip <NAME>       Group Skip file or dir
    -gx|-gregex <EXPR>      Group Skip using regular expressions
    -js                     Use javascript for sorting [default]
    -nojs                   Use static html for sorting
    -xml                    Export catalog to .xml files
    -nosubs                 Clear subtitle search site list
    -nolink                 Clear custom links list
    -a|-automatch           Auto guess and report exact matches [default]
    -na|-noautomatch        Disable auto match
    -m|-missing             Report folders with missing info [default]
    -nm|-nomissing          Don't report missing info
    -mm|-missmatch          Report guessed exact matches as missing
    -mf|-matchfirst         Match first if multiple matches exists
    -my|-matchyear          Match also folders with missing year
    -mfn|-matchfilename     Match also by filename [default]
    -nfn|-nomatchfilename   Don't match by filename
    -aka                    Match AKA titles (other language,..)
    -noaka                  Disable AKA titles [default]
    -as|-autosave           Save auto guessed exact matches
    -cachedays <NUM>        Number of days to cache pages [default: $max_cache_days]
    -theme <NAME>           Select theme name [default: $opt_theme]
    -origtitle              Use original movie title
    -deftitle               Use default (regional) movie title [default]

  Presets:
    skip list: [@skiplist]
    regex skip: [@rxskiplist]
    media ext: [@media_ext]
    codec tags: [@codec]
    cache dir: [$imdb_cache]
    cache days: [$max_cache_days]
    output: [$base_path]
USAGE_LONG
    }

# -codec   Add codec tag

}

sub parse_opt
{
    if (!scalar @_) {
        usage;
        exit;
    }
    while (my $opt = shift) {
        my $arg = $_[0];
        print_log "ARG: '$opt' ($arg)";
        if ($opt eq "-V" or $opt eq "-version" or $opt eq "--version") {
            version;
            exit;
        }
        if ($opt eq "-h" or $opt eq "-?"
                or $opt eq "-help" or $opt eq "--help" ) {
            usage ($opt =~ /-help/);
            exit;
        }
        if ($opt eq "-ih" or $opt eq "-ihelp") {
            print_ihelp;
            exit;
        }
        if (set_opt($opt, $arg)) {
            # arg was used
            shift;
        }
    }
    if (!$ndirs) {
        print_error "No directory specified!";
        exit_cfg;
    }
}

sub makedir
{
    my $dir = shift or return;
    -d $dir or mkdir $dir or abort "Can't mkdir $dir";
}

sub init
{
    $base_path = normal_path($base_path);
    if ($base_path =~ /^(.*\/)([^\/]*)$/) {
        $base_dir = $1;
        $base_name = $2;
    } else {
        $base_dir = "";
        $base_name = $base_path;
    }
    if (!$base_name) {
        abort "Missing file name in base path: $base_path";
    }
    $base_path = $base_dir . $base_name;
    $image_cache = $base_dir . $image_dir;
    makedir $base_dir;
    makedir $imdb_cache;
    makedir $image_cache;
    if ($have_term) {
        my ($width) = GetTerminalSize();
        if ($width >= 40 and $width <= 300) { $columns = $width; }
    }
    print_debug "Base dir: '$base_dir' name: '$base_name'";
    print_debug "Cache IMDB: '$imdb_cache' Image: '$image_cache'";
    print_debug "Cache age: $max_cache_days";
    print_debug "Terminal width: $columns";
    if ($opt_aka) {
        $IMDB::Movie::FIND_OPT = "&site=aka";
    }
    print_debug "AKA: '", $IMDB::Movie::FIND_OPT, "'";
}

sub open_log {
    open $F_LOG, ">", $scan_log;
    print_log "$progname $progver";
    print_log "Perl: ", $^X, " ", sprintf("v%vd", $^V), " ", $^O;
    print_log "CYGWIN='", $ENV{CYGWIN}, "'";
}


###############################

### Main

open_log;

parse_opt(@ARGV);

init;

do_scan;

get_user_votes;

print_report;

print_note "\nDONE.\n";

if ($opt_i) {
    interactive;
}

close $F_LOG;


# vim:expandtab
