#!/usr/bin/perl

=copyright

    Simple Movie Catalog 1.0.3
    Copyright (C) 2008 damien.langg@gmail.com

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
use LWP::Simple;
#use IMDB_Movie;
push @INC, $FindBin::Bin;
push @INC, $FindBin::Bin . "/lib";
require "IMDB_Movie.pm";

### Globals

my $progver = "1.0.3";
my $progbin = "moviecat.pl";
my $progname = "Simple Movie Catalog";
my $progurl = "http://smoviecat.sf.net/";
my $author = 'damien.langg@gmail.com';

my $prog_dir = $FindBin::Bin;
my $imdb_cache = "$prog_dir/imdb_cache";
my $scan_log = "$prog_dir/scan.log";
my $image_dir = "images";
my $image_cache;
my $base_path = "report/movies";
my $base_name;
my $base_dir;

my @parse_ext = qw( nfo txt url desktop );

my @media_ext = qw( mpg mpeg mpe avi mov qt wmv mkv vob
        nfo rar iso bin cue srt sub );

my @codec = qw(
        cam ts r5 dvdscr dvdrip dvd dvd9 cd1 cd2
        hdtv hddvdrip hddvd bluray bd5 bd9
        vcd xvid divx x264 matroska wmv
        dts dolby ac3 vorbis mp3 sub
        720p 1080p hd hidef
        );

my $opt_i = 0; # interactive
my $opt_auto = 1;       # Auto guess and report exact matches
my $opt_miss = 1;       # Report folders with missing info
my $opt_miss_match = 0; # Report guessed exact matches as missing
my $opt_auto_save = 0;  # Save auto guessed exact matches
my $opt_group_table = 1; # use table for groups
my $verbose = 1;

my %movie;  # movie{id}
my @group;  # group list - array of ptr to mlist
my $ngroup;
my $pgroup; # ptr to current group
my $pmlist; # current group movie list - ptr to hash
my %all_dirs;   # visited dirs
my $ndirs;
#my %nfo_noid;
#my $nfo_no_id;
# global skip: sample subs subtitles
my @skiplist = qw( sample subs subtitles cover covers );
my @rxskiplist = qw( /subs-.*/ /\W*sample\W*/ );
my $F_HTML;
my $F_LOG;

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
    print $F_LOG $line, "\n";
}

sub print_error {
    print_log "ERROR: ", @_;
    print "ERROR: ", @_;
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


###############################

### Scan


sub getfile {
  my $filename = shift;
  open F, "< $filename" or return undef;
  my $contents;
  {
    local $/ = undef;     # Read entire file at once
    $contents = <F>;      # Return file as one single `line'
  }                       # $/ regains its old value
  close F;
  return \$contents; # return reference
}

sub cache_imdb_id
{
    my $id = shift;

    my $html_file = $imdb_cache . "/imdb-$id.html";
    my $html;
    if ($html = getfile($html_file)) {
        print_debug "Using Cached: $html_file\n";
        print_note " ";
    } else {
        print_debug "Connecting to IMDB...\n";
        print_note ".";
        $html = IMDB::Movie::get_page_id($id);
        if ($html and open HTML_F, "> $html_file") {
            print_debug "Write Cache: $html_file\n";
            print HTML_F $$html;
            close HTML_F;
        }
    }

    return $html;
}

sub cache_imdb_find
{
    my ($title, $year) = @_;

    my $fname = lc("$title ($year)");
    $fname =~ tr[:/\\][-];
    my $html_file = $imdb_cache . "/imdb_find-$fname.html";
    my $html;
    if ($html = getfile($html_file)) {
        print_debug "Using Cached: $html_file\n";
        print_note " ";
    } else {
        print_debug "Connecting to IMDB...\n";
        print_note ".";
        $html = IMDB::Movie::get_page_find($title, $year);
        if ($html and open HTML_F, "> $html_file") {
            print_debug "Write Cache: $html_file\n";
            print HTML_F $$html;
            close HTML_F;
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
    if (!$m or !$m->id or !$m->img) {
        print_note "-";
        return 1;
    }
    my $img_file = $image_cache . "/" . img_name($m->id);
    if ( -e $img_file ) {
        print_note " ";
        return 1;
    }
    print_note ".";
    my $image = get($m->img);
    if (!$image) {
        print_error "Getting image: ", $m->img, "\n";
        return 0;
    }
    if (open F_IMG, ">:raw", $img_file) {
        print_debug "Write Image Cache: $img_file\n";
        print F_IMG $image;
        close F_IMG;
    } else {
        print_error "Saving image: ", $img_file, "\n";
        return 0;
    }
    return 1;
}

sub getmovie
{
    my $id = shift;
    my $m = $movie{$id};

    if ($m) { return $m;}

    my $html = cache_imdb_id($id);
    if (!$html) {
        print_log "*** Error: get imdb $id\n";
        print_note " FAIL";
        return undef;
    }
    $m = IMDB::Movie->new_html($id, $html);
    if (!$m) {
        print_log "*** Error: parse imdb $id\n";
        print_note " FAIL";
        return undef;
    }
    cache_image($m);
    return $movie{$id} = $m;
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

sub findmovie
{
    my ($title, $year) = @_;
    my $html = cache_imdb_find($title, $year);
    if (!$html) {
        print_log "*** Error: find imdb '$title' ($year)\n";
        print_note " FAIL\n";
        return undef;
    }
    my @matches = IMDB::Movie::get_matches($html);
    my $m;
    if (@matches) {
        # search result - cache first hit
        if ($matches[0]->{id}) {
            $m = getmovie($matches[0]->{id});
            # add match list
            $m->{matches} = \@matches;
            # not a direct hit! unless title matches (almost) exactly
            if (match_title($title, $m->title)) {
                # print_debug "\nTITLE EXACT MATCH: $title\n";
                $m->{direct_hit} = 1;
            } else {
                $m->{direct_hit} = 0;
            }
        }
        return $m;
    }
    # direct hit or no match
    my $m = IMDB::Movie->new_html(0, $html);
    if (!$m) {
        print_log "*** Error: parse imdb '$title' ($year)\n";
        return undef;
    }
    cache_image($m);
    $movie{$m->id} = $m;
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
        print_error "Opening '$fname'\n";
        return;
    }
    print $F_INFO "# Generated by $progname $progver #\n\n";
    print $F_INFO $movie->title, " (", $movie->year, ")\n"; #XXX $movie->type
    print $F_INFO IMDB::Movie::get_url_id($movie->id), "\n\n";
    close $F_INFO;
}


sub shorten
{
    my $name = shift;
    my $max = 60;
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
    return $name;
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

sub dir_assign_movie
{
    my ($dir, $movie) = @_;
    my $id = $movie->id;
    $all_dirs{$dir}->{info} = 1;
    $all_dirs{$dir}->{id}{$id} = 1; # $movie
}

sub group_assign_movie
{
    my ($dir, $movie) = @_;
    my $id = $movie->id;
    $pmlist->{$id}->{movie} = $movie;
    $pmlist->{$id}->{location}{$dir}++;
}

sub count_loc
{
    my $id = shift;
    my $num_loc = 0;
    return unless $pmlist->{$id};
    for my $nl (values %{$pmlist->{$id}->{location}}) { $num_loc += $nl; }
    return $num_loc;
}


# find process (wanted)
sub process_nfo
{
    my $fname = $File::Find::name;
    return unless (-f $fname and match_ext($fname, @parse_ext));
    print_debug "PROCESS: $fname\n";
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
            dir_assign_movie($File::Find::dir, $m);
            group_assign_movie($File::Find::dir, $m);
            my $num_loc = count_loc($id);
            if ( $num_loc > 1 ) { print_note "*$num_loc"; }
            print_note " OK\n";
        }
    }
    close $F_NFO;
    if (!$found) {
        # if ( ! -e "imdb.nfo" ) {
        print_detail "$fname: IMDB NOT FOUND\n";
        print_note "$shortname: IMDB NOT FOUND\n";
        # $nfo_no_id++;
        # $nfo_noid{$File::Find::dir}{$fname} = 1;
        # }
    }
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
    for my $name (@_) {
        next if ($name eq "." or $name eq "..");
        my $skip = 0;
        my $sname = normal_path($name);
        my $fname = normal_path($File::Find::dir . "/" . $name);
        # if already visited, pass through only directories,
        # no need to process files again.
        next if ($visited and ! -d $fname);
        # print_debug "filter check: $name\n";
        for my $s (@{$pgroup->{skiplist}}, @skiplist) {
            my $ssname = $sname;
            # equalize slashes
            $s = normal_path($s);
            if ($s =~ m{/}) {
                # slash in skip name, use full path name
                $ssname = substr($fname, -length($s), length($s));
                #print_debug "Skip-search path: $s in: $ssname\n";
            }
            # ignore case
            if (lc($ssname) eq lc($s)) {
                $skip = 1;
                last;
            }
        }
        # append "/" to dirs
        if ( -d $fname ) { $fname .= "/"; }
        for my $re (@{$pgroup->{rxskiplist}}, @rxskiplist) {
            # ignore case
            # use (?-i) in regex to force case sensitive
            if ($fname =~ /$re/i) {
                #print_debug "SKIP RegEx: $re path: $fname\n";
                $skip = 1;
                last;
            }
        }
        if ($skip) {
            my $fn = shorten(" --- " . $File::Find::dir."/".$name);
            print_note "$fn: SKIP\n";
        } else {
            push @list, $name;
        }
    }
    # build relevant list
    # my @relevant = match_ext_list(@list);
    my @relevant;
    for my $name (@list) {
        if (match_ext($name, @media_ext) and -f $File::Find::dir."/".$name) {
            push @relevant, $name;
        }
    }
    if (@relevant) {
        %{$all_dirs{$File::Find::dir}->{relevant}} = map { $_ => 1 } @relevant;
    }
    # print_debug "RELEVANT: ", %{$all_dirs{$File::Find::dir}->{relevant}}, "\n";
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
    return unless ($all_dirs{$parent}->{info});
    print_note shorten("$dir/"), ": Inherit\n";
    $all_dirs{$dir}->{info} = $all_dirs{$parent}->{info};
    $all_dirs{$dir}->{id} = $all_dirs{$parent}->{id};
    for my $id (keys %{$all_dirs{$parent}->{id}}) {
        if ($pmlist->{$id}) {
            # inherit only if present in current group
            $pmlist->{$id}->{location}{$dir}++;
        }
    }
}

sub automatch
{
    my $path = shift;
    my $dir = basename($path);
    my ($title, $year) = path_to_guess($dir);
    if ($title and $year) {
        print_note shorten($path ."/"), ": GUESS\n";
        print_note shorten(" ??? Guess: '".$title."' (".$year.")"), ": ";
        my $msearch = findmovie($title, $year);
        if ($msearch and $msearch->id and $msearch->direct_hit) {
            print_note $msearch->id, " MATCH\n";
            dir_assign_movie($path, $msearch);
            if (!$opt_miss_match) {
                group_assign_movie($path, $msearch);
            }
            if ($opt_auto_save) {
                save_movie($path, $msearch);
            } else {
                $all_dirs{$path}->{guess} = 1;
            }

        } elsif ($msearch) {
            my $nmatch = scalar @{$msearch->matches};
            print_note "Matches: $nmatch\n";
            $all_dirs{$path}->{matches} = $nmatch;
        } else {
            print_note "No Match\n";
        }
    }
}

# find postprocess
sub check_dir_info
{
    # my ($dir, $parent) = fileparse($File::Find::dir);
    my $parent = dirname($File::Find::dir);
    my $dir = basename($File::Find::dir);
    print_debug "CHECK DIR: '$parent' '$dir' $File::Find::dir\n";
    return if (!$parent or $dir eq ".");
    # if already visited, no need to guess again
    #if ($all_dirs{$File::Find::dir}->{guess}) { goto AUTOMATCH; }
    return if ($all_dirs{$File::Find::dir}->{info});
    return if (!$all_dirs{$File::Find::dir}->{relevant});
    # check for rar
    my $rar = "$parent/$dir.rar";
    my $nfo = "$parent/$dir.nfo";
    if ( -e $rar or -e $nfo ) {
        inherit($File::Find::dir, $parent);
        return;
    }
    # check for cd1/cd2
    if ( $dir =~ /^cd\d$/i ) {
        inherit($File::Find::dir, $parent);
        return;
    }
    # automatch
    AUTOMATCH:
    if ($opt_auto) {
        automatch($File::Find::dir);
    }
}

sub do_scan
{
    for my $g (@group) {
        $pgroup = $g; # set current group
        for my $dir (@{$g->{dirs}}) {
            print_note "\n";
            print_info "[ ", $g->{title}, " ] Searching ... $dir\n";
            if ( ! -d $dir ) {
                print_error "Directory not found: '$dir'\n";
                exit 10;
            }
            $pmlist = \%{$g->{mlist}};
            find( { preprocess  => \&filter_dir,
                    wanted      => \&process_nfo,
                    postprocess => \&check_dir_info,
                    no_chdir    => 1 },
                    $dir);
        }
        print_info "Movies found: ", scalar keys %{$pmlist}, "\n";
        # print_info "NFOs without imdb: ", $nfo_no_id, "\n";
    }
    print_note "\n";
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

    print_html << "HTML_HEAD";
<head>
<title>$title</title>
<meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\">
</head>
<body bgcolor=\"$bgcolor\">

HTML_HEAD
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
    return "<a href=\"file://$path\" style=word-wrap:break-word>$link</a>";
}

sub format_movie
{
    my ($m, @location) = @_;

    #print_debug "LOC: ", join ("\n+++", @location), "\n";

    print_html "<table width=100% cellspacing=0 bgcolor=whitesmoke>";
        # border=1 frame=border rules=all

    print_html "<tr>";
    if ($m->img) {
        my $img_file = img_name($m->id);
        my $img_link = $image_dir ."/". $img_file;
        if ( ! -e $image_cache ."/". $img_file ) { $img_link = $m->img; }
        print_html "<td rowspan=4 width=95><img src=\"", $img_link, "\"></td>";
    } else {
        print_html "<td rowspan=4 width=95 height=110 bgcolor=gray align=center>?</td>";
    }

    # style=\"padding-left: 10px\"
    print_html "<td bgcolor=lightblue height=1*><b>&nbsp;",
            "<a href=http://www.imdb.com/title/tt", $m->id, ">",
            $m->title, "</a></b>",
            " (", $m->year, ")";
            #" &nbsp;&nbsp; <i>(", join(' / ',@{$m->genres}), ")</i>";
    print_html "</td></tr>";

    my ($runtime) = $m->runtime; #split '\|', $m->runtime;
    print_html "<tr><td height=1*>"; #"<font size=-1>";
    print_html "Rating: <b>", $m->user_rating, "</b> &nbsp;&nbsp; ",
            "Runtime: <b>", $runtime ? $runtime : "?" , "</b> min",
            " &nbsp;&nbsp; <i>(", join(' / ',@{$m->genres}), ")</i>";
    print_html "</font></td></tr>";

    print_html "<tr><td><font size=-1>";
    print_html $m->plot ? $m->plot : "&nbsp;?";
    #print_html "</font>";
    print_html "</td></tr>";

    print_html "<tr><td height=1*><font size=-2>Location: ";
    my $i = 0;
    my $nloc = scalar @location;
    for my $loc (sort by_alpha @location) {
        $i++;
        if ($nloc > 1) {
            print_html "<br><b>($i)</b> ";
        }
        if ($all_dirs{$loc}->{guess}) {
            print_html "<b>(GUESSED)</b> ";
        }
        print_html format_html_path($loc);
    }
    print_html "</font></td></tr>";

    print_html "</table><br>\n";
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
        # print_html " $dir\n";
        print_html format_html_path($dir);
        my ($title, $year) = path_to_guess($dir);
        print_html "<br> Guessed title: ";
        print_html "<a href=\"", IMDB::Movie::get_url_find($title,$year), "\">";
        print_html "$title</a> (", $year?$year:"?", ")<br>";
        if ($opt_auto and $title and $year) {
            if ($all_dirs{$dir}->{info} and $all_dirs{$dir}->{guess}) {
                my @ids = keys %{$all_dirs{$dir}->{id}};
                my $movie = getmovie($ids[0]);
                print_html "Exact Match:";
                format_movie($movie, $dir);
                $perf_match++;
            } else {
                my $nmatch = $all_dirs{$dir}->{matches};
                if ($nmatch) {
                    print_html "Matches: ", $nmatch;
                } else {
                    print_html "No Match.";
                }
            }
            print_html "<br>";
=com
        } else {
            # show also filename matches
            my @guess = get_guess_list(cut_ext_l(keys %{$all_dirs{$dir}->{relevant}}));
            for my $g (@guess) {
                $title = $g->{title};
                $year = $g->{year};
                print_html "Guessed title: ";
                print_html "<a href=\"", IMDB::Movie::get_url_find($title,$year), "\">";
                print_html "$title</a> (", $year?$year:"?", ")<br>";
            }
=cut
        }
        print_html "<br>";
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
    return "" unless (scalar @group > 1); 
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

sub page_head_sort {
    my ($fbase, $this_fadd, $add, $sname) = @_;
    if ($this_fadd eq $add) {
        print_html "<b>[$sname]</b>";
    } else {
        print_html "<a href=$fbase$add.html>$sname</a>";
    }
}

sub page_start
{
    my ($gname, $fadd) = @_;
    my $gfname = get_gfname($gname);
    my $fname = $base_path . $gfname . $fadd . ".html";

    open $F_HTML, ">", $fname  or  abort "Can't write $fname\n";
    print_note "Writing $fname\n";
    html_start;
    html_head("Movie Catalog" . ($gname ? ": $gname" : ""));

    if (scalar @group > 1) { 
        #print_html "Group:";
        print_html "<table><tr><td valign=top>Group:<td>";
        print_html "<table cellpadding=0 cellspacing=0><tr>" if ($opt_group_table);
        for my $g (@group) {
            my $gnm = scalar keys %{$g->{mlist}};
            print_html "<td>" if ($opt_group_table);
            page_head_group $fadd, $g->{title}, $gname, $gnm;
            if ($g->{separate}) {
                if ($opt_group_table) {
                    print_html "<tr>";
                } else {
                    print_html "<br>";
                }
            }
        }
        if ($opt_miss and scalar @group > 1) {
            print_html "<td>" if ($opt_group_table);
            page_head_group "", "Missing Info", $gname, count_missing;
        }
        print_html "</table>" if ($opt_group_table);
        print_html "</table><br>";
    }

    if ($opt_miss and $gname eq "Missing Info") {
        # no sort menu
    } else {
        my $fbase = "$base_name$gfname";
        print_html "Sort by:";
        page_head_sort $fbase, $fadd, "", "Title";
        page_head_sort $fbase, $fadd, "-rating", "Rating";
        page_head_sort $fbase, $fadd, "-runtime", "Runtime";
        page_head_sort $fbase, $fadd, "-genre", "Genre";
        if ($opt_miss and scalar @group == 1) {
            page_head_sort $fbase, $fadd, "-missinfo", "Missing Info";
        }
        print_html "<br><br>";
    }
}

sub page_end
{
    #print end_html; # end the HTML
    if (scalar @group < 2) {
        print_html "<br>Total: ", scalar keys %{$pmlist}, " Movies<br>";
    }
    print_html "<br><div align=right><font size=-2><i>Generated by ";
    print_html "<a href=\"$progurl\">$progname $progver</a></i></font></div>";
    print_html "</body></html>";
    close $F_HTML;
}

sub print_page
{
    my ($gname, $fadd, $sort_by) = @_;

    page_start($gname, $fadd);

    for my $id (sort $sort_by keys %{$pmlist}) {
        format_movie($pmlist->{$id}->{movie}, keys %{$pmlist->{$id}->{location}});
    }
    if (!%{$pmlist}) {
        print_html "<br><br><ul><i>* No Movies *</i></ul><br><br>";
    }

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
                format_movie($pmlist->{$id}->{movie}, keys %{$pmlist->{$id}->{location}});
            }
        }
    }

    page_end;
}

sub print_page_miss
{
    my ($gname, $fadd) = @_;
    page_start($gname, $fadd);
    report_missing;
    page_end;
}

sub print_report
{
    # if no missing, disable opt_miss
    if (count_missing == 0) { $opt_miss = 0; }

    print_info "Generating catalog...\n";
    for my $g (@group) {
        my $gname = $g->{title};
        $pmlist = \%{$g->{mlist}};
        print_page $gname, "", \&by_title;
        print_page $gname, "-rating", \&by_rating;
        print_page $gname, "-runtime", \&by_runtime;
        print_page_genre $gname;
        if ($opt_miss and scalar @group == 1) {
            print_page_miss $gname, "-missinfo";
        }
    }
    if ($opt_miss and scalar @group > 1) {
        print_page_miss "Missing Info", "";
    }
}


###############################

### Interactive

sub path_to_guess
{
    my $name = basename(shift);
    my $title = $name;
    my $year;
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
    for my $c (@codec) {
        $title =~ s/\W$c\b.*$//i;
    }
    $title =~ s/[^\w']/ /g; # replace non alphanum to space, keep '
    $title =~ s/^ +//;   # strip leading space
    $title =~ s/ +$//;   # strip trailing space
    $title =~ s/ +/ /g;   # strip duplicate space
    return ($title, $year);
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
    opendir(my $dh, $dir) or print_error("opendir $dir\n") and return;
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
        print_error "Missing CMD\n\n";
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
                print_error "Getting full info for [", $ma->{id}, "]\n";
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

    if ($nmiss) {
        goto NEXT_MISS;
    }

    while (1) {
        CHDIR:
        my $dir = $sort_dirs[$cur_dir];
        my @files =();
        if ($all_dirs{$dir}->{relevant}) {
            @files = keys %{$all_dirs{$dir}->{relevant}};
        }
        my @guess = get_guess_list($dir, cut_ext_l(@files));
        # show max 9 guesses
        my $num_guess = scalar @guess > 9 ? 9 : scalar @guess;

        INFO:
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

        CMD:
        print_info "[enter=next missing  q=quit  ?=help]\n";
        print_info "> ";
        my $cmd = get_input;

        if ($cmd eq undef) {  # enter
            if ($cur_dir == scalar @sort_dirs -1) {
                print_info "Last Directory! [", $cur_dir+1, "]\n";
                goto CMD;
            }
            while ($cur_dir < scalar @sort_dirs -1) {
                $cur_dir++;
                NEXT_MISS:
                last if (is_missing($sort_dirs[$cur_dir]));
            }
            goto CHDIR;

        } elsif ($cmd eq "?" or $cmd eq "h" or $cmd eq "help") {
            print_ihelp;

        } elsif ($cmd eq ".") {
            goto INFO;

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
                goto NEXT_MISS;
            }

        } elsif ($cmd =~ /^cd +(.+) *$/) {
            my $arg = $1;
            if (($arg =~ /^\d+$/) and $arg >=1 and $arg <= scalar @sort_dirs) {
                $cur_dir = $arg - 1;
                goto CHDIR;
            } else {
                my $new_dir = find_dir($dir, $arg, @sort_dirs);
                if ($new_dir >= 0 and $new_dir <= scalar @sort_dirs) {
                    $cur_dir = $new_dir;
                    goto CHDIR;
                }
                print_info "Directory '", $arg, "' Not found!\n";
            }

        } elsif ($cmd eq "n") {
            if ($cur_dir < scalar @sort_dirs -1) {
                $cur_dir++;
                goto CHDIR;
            } else {
                print_info "Last Directory! [", $cur_dir+1, "]\n";
            }

        } elsif ($cmd eq "p") {
            if ($cur_dir > 0) {
                $cur_dir--;
                goto CHDIR;
            } else {
                print_info "First Directory! [", $cur_dir+1, "]\n";
            }

        } elsif ($cmd eq "r") {
            print_report;
            print_info "\n";

        } elsif ($cmd =~ /^!(.*)$/) {
            my $run = $1;
            run_cmd($dir, $run);

        } elsif ($cmd =~ /^\d{7}$/) {
            # search by ID            
            goto GO_SEARCH;

        } elsif ($cmd >= 1 and $cmd <= $num_guess) {
            do_search($dir, $guess[$cmd - 1]->{title}, $guess[$cmd - 1]->{year});
            goto INFO;

        } elsif ($cmd =~ /^s +(.+)$/) {
            $cmd = $1;
            goto GO_SEARCH;

        } elsif (length $cmd >3) {
            GO_SEARCH:
            my $title = $cmd;
            my $year;
            if ($title =~ /^(.+) \((\d{4})\)$/) {
                $title = $1;
                $year = $2;
            } elsif ($title =~ /imdb.com\/title\/tt(\d{7})/i) {
                $title = $1;
            }
            do_search($dir, $title, $year);
            goto INFO;

        } else {
            print_info "Unknown cmd: '$cmd'\n";
        }

        goto CMD;
    }
}


###############################

### Options


sub required_arg {
    my ($opt, $arg) = @_;
    if (!$arg) { abort "Missing arg for $opt\n"; }
    return 1;
}

sub set_opt
{
    my ($opt, $arg) = @_;
    my $arg_used = 0;
    my $is_dir;
    #print_debug "opt: $opt ( $arg )\n";

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

    } elsif ($opt eq "-as" or $opt eq "-autosave") {
        $opt_auto_save = 1;

    } elsif ($opt =~ /^-/) {
        abort "Unknown option: $opt\n";

    } else {
        $ndirs++;
        push @{$group[$ngroup]->{dirs}}, normal_path($opt);
        $is_dir = 1;
    }
    print_log("OPT: '$opt'", ($arg_used?" ($arg)":""));
    print_log("DIR: '$opt'") if ($is_dir);
    return $arg_used;
}

sub parse_cfg
{
    my $cfg_name = shift;
    my $F_CFG;
    my ($opt, $arg);
    open $F_CFG, "<", $cfg_name;
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
}

sub version
{
    print_info "$progname $progver\n";
    print_level 2, "IMDB::Movie ", $IMDB::Movie::VERSION, "\n";
    print_info "Copyright 2008, $author\n";
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
    -s|-skip <NAME>         Skip file or dir
    -x|-regex <EXPR>        Skip using regular expressions
    -ns|-noskip             Clear preset skip lists
    -gs|-gskip <NAME>       Group Skip file or dir
    -gx|-gregex <EXPR>      Group Skip using regular expressions
    DIRECTORY               Directory to scan
USAGE

    if (!$long) {
        print_info "    (Use -help for More Options)\n";
    } else {
        print_info << "USAGE_LONG";

  More Options:
    -a|-automatch           Auto guess and report exact matches [default]
    -na|-noautomatch        Disable auto match
    -m|-missing             Report folders with missing info [default]
    -nm|-nomissing          Don't report missing info
    -mm|-missmatch          Report guessed exact matches as missing
    -as|-autosave           Save auto guessed exact matches

  Presets:
    skip list: [@skiplist]
    regex skip: [@rxskiplist]
    media ext: [@media_ext]
    codec tags: [@codec]
    cache dir: [$imdb_cache]
    output: [$base_path]
USAGE_LONG
    }

# -codec   Add codec tag
# -ext     Add media ext

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
        if ($opt eq "-c" or $opt eq "-config") {
            required_arg($opt, $arg);
            parse_cfg($arg);
            shift;
        } elsif (set_opt($opt, $arg)) {
            # arg was used
            shift;
        }
    }
    if (!$ndirs) {
        print_error "No directory specified!\n";
        exit 10;
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
    print_debug "Base dir: '$base_dir' name: '$base_name'\n";
    print_debug "Cache IMDB: '$imdb_cache' Image: '$image_cache'\n";
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

print_report;

print_note "\nDONE.\n";

if ($opt_i) {
    interactive;
}

close $F_LOG;


