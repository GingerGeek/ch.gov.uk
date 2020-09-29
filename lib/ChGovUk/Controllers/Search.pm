package ChGovUk::Controllers::Search;

use CH::Perl;
use Mojo::Base 'Mojolicious::Controller';
use CH::Util::Pager;

our $JSON_PAGE_SIZE = 20;
our $DEFAULT_PAGE_SIZE = 20;

# Mapping between search type and Net::CompaniesHouse search method
our %search_method = (
    'all'                   => '',
    'companies'             => 'companies',
    'officers'              => 'officers',
    'disqualified-officers' => 'disqualified_officers' ,

);

# Acts as a filter to format numbers in Xslate templates
sub number {
	my ($self, $in) = @_;
	$in =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	return $in;
}

# Search results page
sub results {
    my ($self) = @_;

    # FIXME : my $wants_json  = $self->stash('format') eq 'json';
    my $wants_json  = $self->req->headers->accept =~ /json/gi;

    my $query = $self->param('q');
    
    # use the search type, or the previous search type (pst) - otherwise default 
    my $search_type = $self->param('search_type') || 'all';

    # If we are doing a search that inherites the 'type' that was used in the last search, then get that out of the session,
    # otherwise, it is all. This is route /search/repeat
    if( $search_type eq 'repeat' ) {
        $search_type = $self->session('pst') || 'all';
    }

    # remember the previous search type (pst) for next time
    $self->session(
        'pst' => $search_type,
    );
    
    # pass the search type to the template for a different form action
    $self->stash(
        'search_type'   => $search_type,
        'title'         => ($query) 
                        ? $query . ' - Search Companies House' 
                        : 'Search Companies House' 
    );

    my $page_limit    = $self->config->{elasticsearch}->{max_pages}   || 2500;
    my $results_limit = $self->config->{elasticsearch}->{max_results} || 50000;

	$query =~ s/^\s+//;
	$query =~ s/\s+$//;
	$query =~ s/\s+/ /sg;

    # nothing requested, so return nothing
    if (length $query == 0){
	    trace "Render no results for %s", $wants_json ? 'JSON' : 'HTML' [Search];
	    if ($wants_json) {
	        $self->render(json => {hits=>{ hits => [] }} );
	    } else {
            $self->stash(results => { kind => "search#$search_type" });
	        $self->render(template => 'search/noresults');
	    }
	    return;
	}

    # Pager with scrolling through page numbers functionality turned off
    my $page = $self->param('page') || 1;
    $page = 1 if $page < 1;
    my $page_size   = $wants_json ? $JSON_PAGE_SIZE : $self->param('pagesize')   || $DEFAULT_PAGE_SIZE;
    my $pager       = CH::Util::Pager->new(
        entries_per_page => $page_size,
        current_page => $page,
        scroll_flag => 0
    );

    trace "Query term [%s]", $query [Search];
    trace "Page [%s], page size [%s]", $page, $page_size [Search];

    my $args = {
        'q'				=> $query,
        'num'			=> $page_size,
        'start_index'	=> ($page-1) * $page_size
    };

    my $callbacks = {
        failure => sub {
            my ($api, $tx) = @_;
            my $error_code = $tx->error->{code} // 0;
            my $error_message = $tx->error->{message} // 0;
            my $message = 'Error '.(defined $error_code ? "[$error_code] " : '').'retrieving search results: '.$error_message;
            error "Failure: $message" [Search];
            if ( $error_code eq '416' ){
                $self->render('error', error => "invalid_request", description => "You have requested a page outside of the available result set", status => 416  ) if $self->accepts('html');
            } else {
                $self->render('error', error => "internal_error", description => "The search service is currently unavailable", status => 500 ) if $self->accepts('html');
            }
        },

        success => sub {
            my ($api, $tx) = @_;

            # do not index search results pages
            $self->stash(noindex => 1);

            my $json_results = $tx->res->json;
            trace "Response json is: %s", d:$json_results;

            # FIXME Feels hacky that we need to format the date of birth here so that
            # it effects both server side and client side template rendering.
            if ($search_type eq 'officers' or $search_type eq 'all') {
                for (@{ $json_results->{items} }) {
                    # We only show the full DOB for disqualified officers, so if we ARE NOT a disq officer, supress the DOB day.
                    if ($_->{kind} ne 'searchresults#disqualified-officer' && exists $_->{date_of_birth} && defined $_->{date_of_birth}) {
                        my $month = sprintf '%02s', $_->{date_of_birth}->{month};
                        my $year  = $_->{date_of_birth}->{year};
                        my $dob   = "$year-$month-01";

                        # FIXME We should be doing this in the view I guess, but I'm
                        # not sure how we can format the date using mustache
                        $_->{date_of_birth} = $self->isodate_as_string($dob, "%B %Y");
                    }
                }
            }

            if ($wants_json) {
                # Proxy ES for speed
                debug "Rendering JSON" [SEARCH];
                trace "JSON content: %s", d:$json_results [Search];
                $self->render(json => $json_results );
            }
            else {
                $json_results->{numPages} = $self->_calculate_number_of_pages($json_results);
                $json_results->{searchTerm} = $query;
                $self->stash(results => $json_results);

	            if (not defined $json_results->{total_results} or $json_results->{total_results} == 0) {
	                trace "render no results page" [Search];
	                $self->render(template => 'search/noresults');
                    return;
	            }
	            else {
	                trace "render results page" [Search];
	                $pager->total_entries( $json_results->{total_results} > $results_limit ? $results_limit : $json_results->{total_results} );
	                my $total_pages = $json_results->{total_results} / $pager->{entries_per_page};

                  $total_pages = $page_limit if $total_pages > $page_limit; # limit number of pages
                  $total_pages = 1 + int $total_pages if $total_pages != int $total_pages;

                  my $paging = {
                      current_page        => $pager->current_page,
                      pages_in_set        => $pager->pages_in_set,
                      next_page           => $pager->next_page,
                      previous_page       => $pager->previous_page,
                      entries_per_page    => $pager->entries_per_page,
                      total_entries       => $pager->total_entries,
                      total_pages         => $total_pages,
                      show_pager          => $total_pages > 1,
                      page_limit          => $page_limit,
                      results_limit       => $results_limit,
                  };

                  $self->stash(
                      pager      => $paging,
                      total_hits => $json_results->{total_results},
                  );
                  $self->render;
                }
            }
        },

        error => sub {
            my ($api, $error) = @_;
            my $message = 'Error retrieving search results: '.$error;
            error "%s", $message [Search];
            $self->render_exception($message);
        },
    };

    my $method = $search_method{$search_type} // '';
    trace "Executing query for search type: %s", d:$search_type;

    if ($method) {
        $self->ch_api->search->$method($args)->get->on( %$callbacks )->execute;
    } else {
  	    $self->ch_api->search($args)->get->on( %$callbacks )->execute;
    }

    return $self->render_later;
}

# ---------------------------------------------------------------------------------------------------
# Take the matches array for a title, and insert strong tags into the right place (called from template).
sub format_title {
    my ($self, $result) = @_;

    my $t       = $result->{title};
    my $entries = exists $result->{matches} ? $result->{matches}->{title} : undef;
    my $i;

    while( $entries && @$entries ) {

        $i = pop @$entries;
        $t = substr( $t, 0, $i) . '</strong>' . substr( $t, $i);

        $i = pop @$entries;
        $t = substr( $t, 0, $i - 1) . '<strong>' . substr( $t, $i - 1);
    }

    return $t;
}

# ---------------------------------------------------------------------------------------------------
# Embolden the description (used in templates)
sub format_description {
    my ($self, $result) = @_;

    my $d = $result->{description};

    # external_registration_number should currently be digits only so could be added to regex this way
    # but this means it won't work if the format ever deviates in future, hence the explicit check here
    if (defined $result->{external_registration_number}) {
        $d =~ s/^(.+)($result->{external_registration_number})(.+)?$/$1<strong>$2<\/strong>$3/go;
    }

    $d =~ s/^(\w{8,8}\s+-\s+.+\s+-\s+)(.+)$/$1<strong>$2<\/strong>/go;
    $d =~ s/^(\w{8,8})/<strong>$1<\/strong>/go;
    return $d;
}


# ---------------------------------------------------------------------------------------------------
# Take the matches array for a title, and insert strong tags into the right place.
sub _create_highlighting {
    my ($self, $result) = @_;


    if ( $result->{matches} ) {

        foreach my $field ( keys %{ $result->{matches} } ){

            my $index;
            my $entries = exists $result->{matches}->{$field} ? $result->{matches}->{$field} : undef;

            while( $entries && @$entries ) {

                $index = pop @$entries;
                $result->{$field} = substr( $result->{$field}, 0, $index) . '</strong>' . substr( $result->{$field}, $index);

                $index = pop @$entries;
                $result->{$field} = substr( $result->{$field}, 0, $index - 1) . '<strong>' . substr( $result->{$field}, $index - 1);
            }

        }
    }
    #return $result;
}

# ---------------------------------------------------------------------------------------------------

sub _calculate_number_of_pages {
    my ($self, $results) = @_;

    my $pages = 0;
    # avoid division by zero
    if (defined $results->{items_per_page} and $results->{items_per_page}) {
        $pages = int($results->{total_results} / $results->{items_per_page} );
        # add one page for the last non-full page
        $pages++ if $results->{total_results} % $results->{items_per_page};
    }

    return $pages;
}


1;

=head1 NAME

ChGovUk::Controllers::Search

=head1 SYNOPSIS

    use ChGovUk::Controllers::Search;

    my $search = ChGovUk::Controllers::Search->new();

=head1 DESCRIPTION

=head1 METHODS

=head2 results2 ()


Example

    $search->results2();


=cut
