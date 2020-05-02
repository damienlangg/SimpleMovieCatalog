#!/usr/bin/perl

=copyright

    Copyright (C) 2008-2016 damien.langg@gmail.com

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

###############################

### Interactive

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
    print_debug("MOVIE: ", Dumper($mfound));
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
    print_info "\n===== Interactive (debug) mode =====\n";

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
                print_error "open $fign $!";
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

1;

# vim:expandtab
