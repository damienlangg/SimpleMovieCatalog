package IMDB::Movie;

use strict;
use vars qw($VERSION $AUTOLOAD @MATCH $ERROR $FIND_OPT $old_html $download_func);

use Carp;
use LWP::Simple;
use HTML::TokeParser;
use Data::Dumper;
use HTML::Tagset ();

$VERSION = '0.35';
$ERROR = "";
@MATCH = ();
$FIND_OPT = ""; # "&site=aka"
$old_html = 0;
$download_func = \&download_page_id;

sub error {
    my $preverr = $ERROR;
    $ERROR = shift;
    # carp $ERROR;
    return $preverr;
}

sub new {
    my ($class, $key, $year, $site) = @_;
    @MATCH = ();
    chomp($key);
    carp "can't instantiate $class without id or keyword" unless $key;
    $site ||= 'www';
    # my $parser;
    my $html;
    my $id;
    if ($key =~ /^\d{7}$/) {
        $id = $key;
        # $parser = _get_toker_id($id, $site) or return undef;
        $html = get_page_id($id, $site) or return undef;
    } else {
        # $parser = _get_toker_find($key, $year, $site) or return undef;
        $html = get_page_find($key, $year, $site) or return undef;
    }
    #print ("IMDB id: $id\n");
    # return _new_parser($class, $id, $parser);
    return new_html($class, $id, $html);
}

sub unqote_and_strip_space
{
    my $str = shift;
    $str =~ s/^ *//;
    $str =~ s/ *$//;
    if ($str =~ /^".*"$/)
    {
        $str =~ s/^"//;
        $str =~ s/"$//;
    }
    $str =~ s/^ *//;
    $str =~ s/ *$//;
    return $str
}

sub new_html {
    my ($class, $id, $html) = @_;
    @MATCH = ();
    chomp($id);
    carp "can't instantiate $class without html" unless ($html);
    my $parser = _get_toker_html($html);
    my ($title, $type, $year, $newid, $newhtml);

    $old_html = 0; # assume it's new html formatting

    # get the ball rolling here
    ($parser, $title, $type, $year, $newid, $newhtml) = _title_year_search($parser);

    # need better way to handle errors, maybe?
    if (!$parser) {
        error "$id turned up no matches";
        # print "$id turned up no matches";
        # exit if ($id);
        return undef;
    }
    if ($newid) {
        # print STDERR "NEW ID: $newid ($id)\n";
        $id = $newid; 
    }
    if ($newhtml) {
        # print STDERR "NEW HTML: $newhtml ($id)\n";
        $html = $newhtml; 
    }
    # print STDERR "IMDB ID: $id\n";

    $title = unqote_and_strip_space($title);

    my $self = {
        title       => $title,
        year        => $year,
    };
    if (!$id) { $id      = _get($html, \$parser, "id", \&_id); }
    $self->{id}          = $id;
    $self->{otitle}      = _get($html, \$parser, "header", \&_header);
    $self->{runtime}     = _get($html, \$parser, "runtime", \&_runtime, \&_runtime_old);
    $self->{img}         = _get($html, \$parser, "img", \&_image);
    $self->{user_rating} = _get($html, \$parser, "rating", \&_user_rating, \&_user_rating_old);
    $self->{photos}      = _get($html, \$parser, "photos", \&_photos) || [];
    $self->{plot}        = _get($html, \$parser, "story", \&_storyline);
    if (!$self->{plot}) {
        $self->{plot}    = _get($html, \$parser, "plot", \&_plot);
    }
    $self->{genres}      = _get($html, \$parser, "genre", \&_genre) || [];
    #$self->{directors}   = _get($html, \$parser, "direct", \&_person) || {};
    #$self->{writers}     = _get($html, \$parser, "writer", \&_person) || {};
    #$self->{cast}        = _get($html, \$parser, "cast", \&_cast) || {};
    #if (!$type && $old_html) {
    #    $type            = _get($html, \$parser, "type", \&_type_old);
    #}
    $self->{type}        = $type;
    $self->{direct_hit}  = !$newid;
    $self->{matches}     = \@MATCH;
    # note: [] = ref to empty array
    # note: {} = ref to empty hash

    return bless $self, $class;
}

sub _get
{
    my ($html, $parse_r, $name, $func, $func_old) = @_;
    my $val = &$func($$parse_r);
    if (!defined $val) {
        # if func returns undef then rewind parser and retry
        # print "\nRETRY: $name\n";
        $$parse_r = _get_toker_html($html);
        $val = &$func($$parse_r);
        if (!defined $val) {
            if ($func_old) {
                # print "OLD: $name\n";
                $$parse_r = _get_toker_html($html);
                $val = &$func_old($$parse_r);
                if ($val) {
                    # looks like old style html format
                    $old_html = 1;
                }
            }
        }
        # if (!defined $val) { print "FAIL: $name\n"; }
        # print "RET: $val\n";
    }
    return $val;
}

sub to_string() {
    my $self = shift;
    return sprintf("%s (%s) by %s", 
        $self->{title},
        $self->{year},
        join(', ',@{$self->{director}}),
    );

}

sub as_HTML_Template {
    my $self = shift;
    require('Clone.pm');
    my $clone = Clone::clone($self);
    my %d = %{$clone->directors};
    my %w = %{$clone->writers};
    my %c = %{$clone->cast};
    $clone->{directors} = [ sort{$a->{id}<=>$b->{id}} values %d ];
    $clone->{writers}   = [ sort{$a->{id}<=>$b->{id}} values %w ];
    $clone->{cast}      = [ sort{$a->{id}<=>$b->{id}} values %c ];
    $clone->{genres}    = [ map {name => $_}, @{$clone->genres} ];
    return %$clone;
}

sub director { shift->_merge_names('directors') }
sub writer   { shift->_merge_names('writers') }
sub actor    { shift->_merge_names('cast') }

sub AUTOLOAD {
    my ($self) = @_;
    $AUTOLOAD =~ /.*::(\w+)/ && exists $self->{$1} and return $self->{$1};
    croak "No such attribute: $1";
}

sub DESTROY {}


sub get_vote_history {
    my $url = shift;
    if (not $url =~ /^http:/i) {
        $url = "http://www.imdb.com/mymovies/list?l=" . $url;
    }
    my $content = get($url);
    return undef unless ($content);
    my $uv = parse_vote_history(\$content);
    if ($uv) {
        $uv->{'url'} = $url;
    }
    return $uv;
}

sub parse_vote_history {
    my $html = shift;
    my $parser = _get_toker_html($html);
    my $tag;
    my $user;
    my %vote;
    # user name
    while ($tag = $parser->get_tag('a')) {
        if ($tag->[1]{href} =~ /\/user\//) {
            $user = $parser->get_text();
            last;
        }
    }
    #print "Vote User: $user\n";
    # vote table
    while ($tag = $parser->get_tag('a')) {
        if ($tag->[1]{href} =~ /\/title\/\D*(\d+)/) {
            my $id = $1;
            $parser->get_tag('td');
            $vote{$id} = $parser->get_text();
            #print "Vote $id: ", $vote{$id}, "\n";
        }
    }
    return {'user'=>$user, 'vote'=>\%vote};
}


############################################################################

sub _merge_names { [sort map "$_->{last_name}, $_->{first_name}", values %{shift->{+shift}} ] }

sub _is_search_title {
    my $pagetitle = shift;
    # old: imdb.*search
    # new: find - imdb
    # advanced: imdb: Most Popular Titles Released In 1999 With Title Matching "TITLE"
    return ($pagetitle =~ /find - imdb/i
        || $pagetitle =~ /imdb.*search/i
        || $pagetitle =~ /imdb:.*title matching/i);
}

sub get_matches
{
    my $html = shift;
    my $parser = _get_toker_html($html);
    my ($pagetitle, $year);
    @MATCH = ();
    $parser->get_tag('title');
    $pagetitle = $parser->get_text();
    if (_is_search_title($pagetitle)) {
        # this is a search result!
        _get_lucky($parser);
    }
    return @MATCH;
}

sub _title_year_search {
    my ($parser) = @_;
    my ($pagetitle, $title, $type, $year, $id, $html);

    $parser->get_tag('title') or return undef;
    # $pagetitle = $parser->get_text() or return undef;
    $pagetitle = get_text_html($parser) or return undef;

    if (_is_search_title($pagetitle)) {
        # this is a search result!
        $id = _get_lucky($parser);
        return undef unless ($id);

        # start over
        # $parser = _get_toker_id($id);
        $html = get_page_id($id) or return undef;
        $parser = _get_toker_html($html);
        $parser->get_tag('title');
        $pagetitle = $parser->get_text();
    }

    # old:
    # The Plan (2009/I) (V)
    # "Supernatural" (2005)
    # (500) Days of Summer (2009)
    # LOL (Laughing Out Loud) � (2008)
    # new:
    # The Plan (Video 2009) - IMDb
    # Supernatural (TV Series 2005-�) - IMDb
    # LOL (Laughing Out Loud) � (2008) - IMDb
    # IMDb - Crash (2004)  

    # title: everything till first ( that contains a year
    # but include ( if the title starts with it
    $pagetitle =~ s/^imdb - //i;
    $pagetitle =~ s/ - imdb$//i;
    $pagetitle =~ /^([(]*[^(]+.*)(\([^(]*\d{4}.*)$/ or return undef;
    $title = $1;
    my $rest = $2;
    # year: any 4-digit number inside ()
    $rest =~ /\(.*(\d{4}).*\)/ or return undef;
    $year = $1;
    # optional type: any text following a (
    # stopping at ) or number
    if ($rest =~ /\(([[:alpha:]\s]+).*\)/) {
        $type = $1;
    }
    return ($parser, $title, $type, $year, $id, $html);
}


sub _get_lucky {
    my ($parser) = @_;
    my ($tag,$id);

    # don't textify <img> tags
    $parser->{textify} = ();
    while ($tag = $parser->get_tag('a')) {
        my $href = $tag->[1]->{href};
        next unless $href;
        if (($id) = $href =~ /^\/title\/tt(\d{7})[\/]?/) {
            my $title = $parser->get_text;
            next unless ($title);
            next if ($title eq "[IMG]");
            my $year;
            my $type;
            $parser->get_tag('/a');
            if ($parser->get_text =~ /\((\d{4})\) *(\(.*\))?$/) {
                $year = $1;
                $type = $2;
                # print "TYPE: $type\n";
            }
            $tag = $parser->get_tag();
            if ($tag->[0] eq "small") {
                $type .= $parser->get_text;
                # print "TYPE. $type\n";
            }
            # print "match: $id $title $year $type\n";
            push @MATCH, {id => $id, title => $title, year => $year, type => $type};
        }
    }

    return $MATCH[0]{id};
}


sub _id_old {
    my $parser = shift;
    my ($id,$tag);
    # http://pro.imdb.com/title/tt0000001/
    while ($tag = $parser->get_tag('a')) {
        if ($tag->[1]{href} =~ /pro.imdb.com\/title\/tt(\d{7})/i) {
            $id = $1;
            # print STDERR "FOUND IMDB _ID: $id\n";
            return $id;
        }
    }
    return undef;
}

sub _id {
    my $parser = shift;
    my ($id,$tag);
    # <link rel="canonical" href="http://www.imdb.com/title/tt0000001/" />
    while ($tag = $parser->get_tag('link')) {
        if ($tag->[1]{href} =~ /imdb.com\/title\/tt(\d{7})/i) {
            $id = $1;
            # print STDERR "FOUND IMDB _ID: $id\n";
            return $id;
        }
    }
    return undef;
}

sub _header {
    my $parser = shift;
    my $tag;
    my $stag;
    my $otitle;

    # $tag = _jump_class($parser, "header", "h1") or return undef;
    $tag = _jump_class($parser, "header") or return undef;
    $stag = $tag->[0]; # h1
    while ($tag = $parser->get_tag) {
        if ($tag->[0] =~ /^\/$stag/) {
            return "";
        }
        if ($tag->[0] eq "span" and $tag->[1]->{"class"} eq "title-extra") {
            $otitle = get_text_html($parser);
            $otitle = unqote_and_strip_space($otitle);
            return $otitle;
        }
    }
    return undef;
}


sub _image {
    my $parser = shift;
    my ($tag,$image);

    while ($tag = $parser->get_tag('div')) {
        $tag->[1]->{class} ||= '';
        if ($tag->[1]->{class} =~ /poster/i) {
            $tag = $parser->get_tag('img');
            $image = $tag->[1]->{src};
            last;
        }
    }
    if ($image =~ /\/nopicture\//i) {
        return "";
    }

    return $image;
}


sub _photos
{
    # photos no longer work, return empty list
    return [];
}

sub _photos_old
{
    my $parser = shift;
    my ($tag, @photos);
    _jump_attr($parser, "photos", "h2") or return undef;
    while ($tag = $parser->get_tag()) {
        last if ($tag->[0] eq "/div");
        if ($tag->[0] eq "img" and $tag->[1]->{src}) {
            # print "photo: ", $tag->[1]->{src}, "\n";
            push @photos, $tag->[1]->{src};
        }
    }
    return [ @photos ];
}


sub _person {
    my $parser = shift;
    my ($tag,%name);

    # skip
    while ($tag = $parser->get_tag('h5')) {
        my $tag_text = $parser->get_text('/h5');
        last if ($tag_text =~ /director/i);
        last if ($tag_text =~ /writer/i);
    }
    $parser->get_tag('/h5');

    {
        do {
            $tag = $parser->get_tag();
        } while ($tag->[0] eq 'br' || $tag->[0] eq 'br/' || $tag->[0] eq '/a' );
        last unless $tag->[0] eq 'a';

        my $name = $parser->get_text;
        last if $name eq 'more';
        
        my ($id) = $tag->[1]{href} =~ /(\d+)/;
        my ($f,$l) = split(' ',$name,2);

        $name{$id} = { id => $id, last_name => $l, first_name => $f };
        #print "person: $id $name\n";

        redo;
    }
    return undef if (!%name);
    return {%name};
}

# found = _jump_attr(parser, attr_name, @tag_list)

sub _jump_attr {
    my ($parser, $attr, @tags) = @_;
    my $tag;
    my $val;
    while ($tag = $parser->get_tag(@tags)) {
        $val = $parser->get_text();
        # print "jump($attr,",@tags,") : ", $tag->[0], " : ", $val, "\n";
        # print "FOUND\n" if ($val =~ /$attr/i);
        return $tag if ($val =~ /$attr/i);
    }
    return 0;
}

sub _jump_class {
    my ($parser, $class, @tags) = @_;
    my $tag;
    while ($tag = $parser->get_tag(@tags)) {
        # print "\nTAG[", scalar @{$tag}, "]: ", join(' ',@{$tag}), "\n";
        # is a start tag?
        if (scalar @{$tag} > 2) {
            return $tag if ($tag->[1]->{class} =~ /$class/i);
        }
    }
    return 0;
}

# <span class="hidden" itemprop="ratingValue">-</span>
# <span itemprop="ratingValue">8.4</span>

sub _jump_prop {
    my ($parser, $prop_name, $prop_val, @tags) = @_;
    my $tag;
    while ($tag = $parser->get_tag(@tags)) {
        # print "\nTAG[", scalar @{$tag}, "]: ", join(' ',@{$tag}), "\n";
        # is a start tag?
        if (scalar @{$tag} > 2) {
            if ($tag->[1]->{class} =~ /hidden/i) {
                # skip hidden tags
                # print ("skip: ", $parser->get_text(), "\n");
                next;
            }
            return $tag if ($tag->[1]->{$prop_name} =~ /$prop_val/i);
        }
    }
    return 0;
}

# val = _get_info(parser, attr_name, start_tag, end_tag)

sub _get_info {
    my $parser = shift;
    my $attr = shift;
    my @stags = split(/\|/,(shift || "h5"));
    my @etag = @_; #shift;
    my $stag;
    my $tag;
    my $val;
    # print "get_info(@stags, $attr)\n";
    $tag = _jump_attr($parser, $attr, @stags) or return undef;
    $stag = $tag->[0];
    $parser->get_tag('/'.$stag) or return undef;
    # $val = $parser->get_text(@etag) or return undef;
    $val = get_text_html($parser, @etag) or return undef;
    $val =~ tr/\n//d;
    return $val;
}

sub _type_old {
    my $parser = shift;
    my $tag;
    my $val;
    $tag = $parser->get_tag("h1") or return undef;
    $tag = $parser->get_tag or return undef;
    return "" unless ($tag->[0] eq "span");
    $val = $parser->get_text("/h1");
    # strip year
    $val =~ s/^[^)]*\) *//;
    # type and year range separated by: &#160;
    # translate all non-printables to space
    $val =~ s/[^[:print:]]/ /g;
    # extract type in ()
    if ($val =~ /(\(\w+\))/) {
        return $1;
    }
    # extract tv series
    if ($val =~ /([tv ]*series[\d ?-]*)/i) {
        return $1;
    }
    return "";
}

sub _type {
    # not used, type is returned by _title_year_search
}

sub _genre {
    my $parser = shift;
    my ($tag,@genre);

    # OLD: my $genre = _get_info($parser, "genre", "h5", "/div");
    my $genre = _get_info($parser, "genres:|genre:", "h4|h5", "/div") or return undef;
    # print "\nGENRE: '$genre'\n";
    $genre =~ s/ see more.*$//i;
    $genre =~ s/ more.*$//i;
    $genre =~ s/[^\w|-]//g;
    @genre = split(/\|/, $genre);

    return undef if (!@genre);
    return [ unique(@genre) ];
}


sub _user_rating_old2 {
    my $parser = shift;
    my $tag;
    my $rating;

    _jump_attr($parser, "rating", "h5", "b") or return undef;
    $parser->get_tag("b") or return undef;
    $rating = $parser->get_text() or return undef;
    if ($rating =~ /([\d.]+) *\/ *10/) {
        return $1;
    }
    # no rating
    return "";
}

sub _user_rating_old {
    my $parser = shift;
    my $tag;
    my $rating;

    _jump_class($parser, "rating-rating", "span") or return undef;
    $rating = $parser->get_text() or return undef;
    if ($rating =~ /([\d.]+)/) {
        return $1;
    }
    # no rating
    return "";
}

sub _user_rating {
    my $parser = shift;
    my $tag;
    my $rating;

    # <span itemprop="ratingValue">8.4</span>
    _jump_prop($parser, "itemprop", "ratingValue", "span") or return undef;
    $rating = $parser->get_text() or return undef;
    if ($rating =~ /([\d.]+)/) {
        return $1;
    }
    # no rating
    return "";
}


sub _cast {
    my $parser = shift;
    my ($tag,%name);

    # skip
    while ($tag = $parser->get_tag('h3')) {
        last if ($parser->get_text() =~ /cast/i);
    }

    while ($tag = $parser->get_tag('a')) {
        my $href = $tag->[1]{href};
        if ($href) {
            if ($href =~ /fullcredits/i) {
                last;
            } else {
                my ($id) = $href =~ /\/name\/nm(\d+)/;
                if ($id) {
                    my $name = $parser->get_text;
                    next if ($name eq "" || $name eq "[IMG]");
                    # print "Actor: $id $name\n";
                    my ($f,$l) = split(' ',$name,2);
                    $name{$id} = { id => $id, last_name => $l, first_name => $f };
                }
            }
        }
    }
    return undef if (!%name);
    return {%name};
}

sub _plot_old {
    my $plot = _get_info(shift, "plot", "h5", "a", "/div") or return undef;
    $plot =~ s/[ |]*$//;
    return $plot;
}

sub _plot {
    my $parser = shift;
    my $tag = _jump_attr($parser, "critics:", "span") or return undef;
    $parser->get_tag("p") or return undef;
    # my $plot = $parser->get_text("div") or return undef;
    my $plot = get_text_html($parser, "div") or return undef;
    $plot =~ s/ *\|.*$//;
    # print "\nplot: $plot\n";
    return $plot;
}

sub _storyline {
    # storyline is longer than plot
    my $plot = _get_info(shift, "storyline", "h2", "/p", "em", "span") or return undef;
    $plot =~ s/ *\|.*$//;
    # print "\nstory: $plot\n";
    return $plot;
}

sub _runtime {
    # runtime from technical info section
    # new: h4 old: h5
    my $runstr = _get_info(shift, "runtime", "h4|h5", "/div") or return undef;
    my $runtime;
    if ($runstr =~ /([\d]+)/) { $runtime = $1; }
    return $runtime;
}

sub _runtime_old {
    # runtime from below title ("infobar" class)
    # some movies don't have technical info, but have the runtime below title
    # there is no longer an infobar class
    my $parser = shift;
    my $tag = _jump_class($parser, "infobar", "div") or return undef;
    my $val = $parser->get_text("/div") or return undef;
    if ($val =~ /(\d+) *min/) {
        my $runtime = $1;
        return $runtime;
    }
    return undef;
}


sub get_url_id {
    my ($id,$site) = @_;
    $site ||= "www";
    my $url = "http://$site.imdb.com/title/tt$id";
    return $url;
}

sub download_page_id {
    my ($id,$site) = @_;
    my $url = get_url_id($id, $site);
    my $content = get($url);
    if (!$content) {
        error "can't connect to server $url";
        return undef;
    }
    return \$content;
}

sub get_page_id {
    my ($id,$site) = @_;
    #print "get_page_id($id)\n";
    return $download_func->($id);
}

sub get_url_find {
    my ($key,$year,$site) = @_;
    $site ||= "www";
    my $url;
    # advanced search: http://www.imdb.com/search/title?release_date=1999,1999&title=TITLE
    #  optional: &view=simple
    #my $url  = "http://$site.imdb.com/find?s=all&q=$key";
    if ($year) {
        # use advanced search, release_date=
        $url = "http://$site.imdb.com/search/title?release_date=$year,$year&title=$key";
    } else {
        # simple search &tyear= doesn't work anymore
        $url = "http://$site.imdb.com/find?s=tt&q=$key";
        # if ($year) { $url .= "&tyear=$year"; }
        $url .= $FIND_OPT;
    }
    return $url;
}

sub get_page_find {
    my ($key, $year, $site) = @_;
    my $url = get_url_find($key, $year, $site);
    my $content = get($url);
    if (!$content) {
        error "can't connect to server $url";
        return undef;
    }
    return \$content;
}

sub _get_toker_html {
    my $content_ref = shift;
    return undef unless $content_ref;
    return HTML::TokeParser->new($content_ref);
}

sub _get_toker_id {
    my $content_ref = get_page_id(@_);
    return _get_toker_html($content_ref);
}

sub _get_toker_find {
    my $content_ref = get_page_find(@_);
    return _get_toker_html($content_ref);
}


sub unique {
    my %seen;
    grep(!$seen{$_}++, @_);
}

# modified get_text to not decode html unicode entries and trim whitespace

sub get_text_html {
    my $self = shift;
    my @text;
    while (my $token = $self->get_token) {
	my $type = $token->[0];
	if ($type eq "T") {
	    my $text = $token->[1];
	    # decode_entities($text) unless $token->[2];
	    push(@text, $text);
	} elsif ($type =~ /^[SE]$/) {
	    my $tag = $token->[1];
	    if ($type eq "S") {
		# if (defined(my $text = _textify($self, $token))) {
		if (defined(my $text = HTML::TokeParser::_textify($self, $token))) {
		    push(@text, $text);
		    next;
		}
	    } else {
		$tag = "/$tag";
	    }
	    if (!@_ || grep $_ eq $tag, @_) {
		 $self->unget_token($token);
		 last;
	    }
	    push(@text, " ")
		if $tag eq "br" || !$HTML::Tagset::isPhraseMarkup{$token->[1]};
	}
    }
    my $t = join("", @text);
    # only decode &nbsp;
    $t =~ s/&nbsp;/ /g;
    # trim whitespace
    $t =~ s/^\s+//;
    $t =~ s/\s+$//;
    $t =~ s/\s+/ /g;
    return $t;
}

1;

=pod

=head1 NAME

IMDB.pm - module to fetch movie info from www.imdb.com

=head1 DESCRIPTION

This is a module that uses LWP and HTML::TokeParser to
parse the web page for the requested movie. You can use
an IMDB identification number or the name of the movie.
IMDB.pm will try to return the best match.

=head1 SYNOPSIS

  use strict;
  use IMDB::Movie;

  my $movie = IMDB::Movie->new(92610);
  print join("|",
    $movie->title, 
    $movie->id, 
    $movie->year, 
    join(';',@{$movie->director}),
    join(';',@{$movie->writer}),
    join(';',@{$movie->genres}),
    $movie->user_rating,
    $movie->img,
  ), "\n";

  sleep 5;

  # now more compatible with HTML::Template!
  $tmpl->param($movie->as_HTML_Template);

=head1 METHODS 

=over 4

=item B<new>

  my $movie_by_id = IMDB::Movie->new(92610);

  my $movie_by_title = IMDB::Movie->new('Bad Taste');

Instantiates the object and fetches the movie. IMDB::Movie prefers
the IMDB identification number, but you can pass the name of the
movie with moderate success. Note that this causes an extra page
fetch as IMDB::Movie parses the search results.

You can also specify which 'site' you want to search:

  my $movie = IMDB::Movie->new('Alien','uk');

This will search B<uk.imdb.com> instead of B<www.imdb.com>, the default.

=item B<title>

  my $title = $movie->title;

Returns the IMDB given title of this movie.

=item B<id>

  my $id = $movie->id;

Returns the IMDB id of this movie.

=item B<year>

  my $year = $movie->year;

Returns the year the movie was released.

=item B<director>

  my @director = @{$movie->director};

Returns an anonymous array reference of director names.

=item B<directors>

  my %director = %{$movie->directors};
  for my $id (keys %director) {
     print $director{$id}{first_name};
     print $director{$id}{last_name};
  }

Returns an anonymous hash reference whose keys are IMDB
name id's and whose values are anonymous hash references
containing first and last name key/value pairs.

=item B<writer>

  my @writer = @{$movie->writer};

Returns an anonymous array reference of writer names.

=item B<writers>

  my %writer = %{$movie->writers};
  for my $id (keys %writer) {
     print $writer{$id}{first_name};
     print $writer{$id}{last_name};
  }

Return an anonymous hash reference whose keys are IMDB
name id's and whose values are anonymous hash references
containing first and last name key/value pairs.

=item B<cast>

  my %cast = %{$movie->cast};
  for my $id (keys %cast) {
     print $cast{$id}{first_name};
     print $cast{$id}{last_name};
  }

Return an anonymous hash reference whose keys are IMDB
name id's and whose values are anonymous hash references
containing first and last name key/value pairs.

This is for the First Billed cast only, that is, the module
parses out the name from the first page. Possibly in the
future i will parse out the entire crew, but it's doubtful.

=item B<genres>

  my @genres = @{$movie->genres};

Returns an anonymous array reference of genre names.

=item B<user_rating>

  my $user_rating = $movie->user_rating;

Returns the current IMDB user rating as is.

=item B<img>

  my $img = $movie->img;

Returns the url of the image used for this Movie at imdb.com

=item B<matches>

  my @match = @{$movie->matches};

Returns a list of hashes (LoH) containing 'id' and 'title'
key/value pairs for all title matches returned when a seach
by title was performed. For example:

  use IMDB::Movie;
  use CGI qw(:standard);
  my $movie = IMDB::Movie->new('Terminator');
  my @match = @{$movie->matches};

  if (@match) {
     print (
        p('The following matches were found:'),
        ol(
           li([ map
              a(
                 {href => "http://imdb.com/title/tt$_->{id}"},
                 $_->{title}
              ), @match
           ])
        ),
     );
  }

will produce an HTML ordered list of anchored links.

=item B<as_HTML_Template>

  my %t_movie = $movie->as_HTML_Template;

This simply returns a hash that is a clone of the IMDB::Movie object.
The only difference between the clone and the original is the
clone's directors, writers, and genres methods return HTML::Template
ready data structures. Just use Data::Dumper and see the ouput
for yourself - if you use HTML::Template, you'll know what to do
with it.

=back

=head1 BUGS

If you have found a bug, typo, etc. please visit Best Practical Solution's
CPAN bug tracker at http://rt.cpan.org:

E<lt>http://rt.cpan.org/NoAuth/Bugs.html?Dist=IMDB-MovieE<gt>

or send mail to E<lt>bug-IMDB-Movie#rt.cpan.orgE<gt>

(you got this far ... you can figure out how to make that
a valid address ... and note that i won't respond to bugs
sent to my personal address any longer)

=head1 AUTHOR 

Jeffrey Hayes Anderson

=head1 CREDITS

Heavily reworked to make it usable with 2008-2013 IMDB:

   - damien.langg@gmail.com

Various suggestions and typo spottings:

   - Danilo Aghemo
   - ArteQ 2
   - Marvin Baschangel
   - V. Ray Krebs III
   - Codrut C. Racosanu

=head1 DISCLAIMER

This module should be used VERY SPARSLEY. The good people at
the Internet Movie Database provide access to their websites
for free, and i do not want this module to be used in an
irresponsible manor.

Also, screen-scraping a web site does not make for a long living
application. Any changes to IMDB's design could potentially break
this module. I give no garuantee that i will maintain this module,
but i will garuantee that i may just delete this module with no
notice. 

=head1 COPYRIGHT

Movie Data Copyright (c) 1990-2008 Internet Movie Database Inc.

Module Copyright (c) 2004 Jeffrey Hayes Anderson.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

=tokeparser quick reference

$p->get_tag
$p->get_tag( @tags )

returns:
start tag: [$tag, $attr, $attrseq, $text]
end tag:   ["/$tag", $text]
not found: undef

where $attr is a hash reference, $attrseq is an array reference and the rest are plain scalars.

=cut

# vim:expandtab
