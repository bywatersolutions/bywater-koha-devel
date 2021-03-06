package C4::XISBN;
# Copyright (C) 2007 LibLime
# Joshua Ferraro <jmf@liblime.com>
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use XML::Simple;
#use LWP::Simple;
use C4::Biblio;
use C4::Koha;
use C4::Search;
use C4::External::Syndetics qw(get_syndetics_editions);
use LWP::UserAgent;
use HTTP::Request::Common;

use strict;
#use warnings; FIXME - Bug 2505
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

BEGIN {
	require Exporter;
	@ISA = qw(Exporter);
	@EXPORT_OK = qw(
		&get_xisbns
        &get_biblionumber_from_isbn
	);
}

sub get_biblionumber_from_isbn {
    my $isbn = shift;
   	$isbn.='%';
    my @biblionumbers;
    my $dbh=C4::Context->dbh;
    my $query = "SELECT biblionumber FROM biblioitems WHERE isbn LIKE ? LIMIT 10";
    my $sth = $dbh->prepare($query);
    $sth->execute($isbn);
	return $sth->fetchall_arrayref({});
}
=head1 NAME

C4::XISBN - Functions for retrieving XISBN content in Koha

=head1 FUNCTIONS

This module provides facilities for retrieving ThingISBN and XISBN content in Koha

=cut

sub _get_biblio_from_xisbn {
    my $xisbn = shift;
    my $dbh = C4::Context->dbh;

    my ( $errors, $results, $total_hits ) = C4::Search::SimpleSearch( "nb=$xisbn", 0, 1 );
    return unless ( !$errors && scalar @$results );

    my $record = C4::Search::new_record_from_zebra( 'biblioserver', $results->[0] );
    my $biblionumber = C4::Biblio::get_koha_field_from_marc('biblio', 'biblionumber', $record, '');
    return unless $biblionumber;

    my $xbiblio = GetBiblioData($biblionumber);
    return unless $xbiblio;
    $xbiblio->{normalized_isbn} = GetNormalizedISBN($xbiblio->{isbn});
    return $xbiblio;
}

=head1 get_xisbns($isbn);

=head2 $isbn is an ISBN string

=cut

sub get_xisbns {
    my ( $isbn ) = @_;
    my ($response,$thing_response,$xisbn_response,$syndetics_response);
    # THINGISBN
    if ( C4::Context->preference('ThingISBN') ) {
        my $url = "http://www.librarything.com/api/thingISBN/".$isbn;
        $thing_response = _get_url($url,'thingisbn');
    }

	if ( C4::Context->preference("SyndeticsEnabled") && C4::Context->preference("SyndeticsEditions") ) {
    	my $syndetics_preresponse = &get_syndetics_editions($isbn);
		my @syndetics_response;
		for my $response (@$syndetics_preresponse) {
			push @syndetics_response, {content => $response->{a}};
		}
		$syndetics_response = {isbn => \@syndetics_response};
	}

    # XISBN
    if ( C4::Context->preference('XISBN') ) {
        my $affiliate_id=C4::Context->preference('OCLCAffiliateID');
        my $limit = C4::Context->preference('XISBNDailyLimit') || 999;
        my $reached_limit = _service_throttle('xisbn',$limit);
        my $url = "http://xisbn.worldcat.org/webservices/xid/isbn/".$isbn."?method=getEditions&format=xml&fl=form,year,lang,ed";
        $url.="&ai=".$affiliate_id if $affiliate_id;
        unless ($reached_limit) {
            $xisbn_response = _get_url($url,'xisbn');
        }
    }

    $response->{isbn} = [ @{ $xisbn_response->{isbn} or [] },  @{ $syndetics_response->{isbn} or [] }, @{ $thing_response->{isbn} or [] } ];
    my @xisbns;
    my $unique_xisbns; # a hashref

    # loop through each ISBN and scope to the local collection
    for my $response_data( @{ $response->{ isbn } } ) {
        next if $response_data->{'content'} eq $isbn;
        next if $isbn eq $response_data;
        next if $unique_xisbns->{ $response_data->{content} };
        $unique_xisbns->{ $response_data->{content} }++;
        my $xbiblio= _get_biblio_from_xisbn($response_data->{content});
        push @xisbns, $xbiblio if $xbiblio;
    }
    return \@xisbns;
}

sub _get_url {
    my ($url,$service_type) = @_;
    my $ua = LWP::UserAgent->new(
        timeout => 2
        );

    my $response = $ua->get($url);
    if ($response->is_success) {
        warn "WARNING could not retrieve $service_type $url" unless $response;
        if ($response) {
            my $xmlsimple = XML::Simple->new();
            my $content = $xmlsimple->XMLin(
            $response->content,
            ForceArray => [ qw(isbn) ],
            ForceContent => 1,
            );
            return $content;
        }
    } else {
        warn "WARNING: URL Request Failed " . $response->status_line . "\n";
    }

}


# Throttle services to the specified amount
sub _service_throttle {
    my ($service_type,$daily_limit) = @_;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(q{ SELECT service_count FROM services_throttle WHERE service_type=? });
    $sth->execute($service_type);
    my $count = 0;

    if ($sth->rows == 0) {
        # initialize services throttle
        my $sth2 = $dbh->prepare(q{ INSERT INTO services_throttle (service_type, service_count) VALUES (?, ?) });
        $sth2->execute($service_type, $count);
    } else {
        $count = $sth->fetchrow_array;
    }

    # we're over the limit
    return 1 if $count >= $daily_limit;

    # not over the limit
    $count++;
    my $sth3 = $dbh->prepare(q{ UPDATE services_throttle SET service_count=? WHERE service_type=? });
    $sth3->execute($count, $service_type);

    return undef;
}

1;
__END__

=head1 NOTES

=cut

=head1 AUTHOR

Joshua Ferraro <jmf@liblime.com>

=cut

