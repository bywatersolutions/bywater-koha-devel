package C4::Utils::DataTables::Patrons::ElasticSearch;

use Modern::Perl;

use Search::Elasticsearch;
use ElasticSearch::SearchBuilder;
use JSON qw( to_json encode_json );

use C4::Branch qw/onlymine/;
use C4::Context;
use C4::Members qw/GetMemberIssuesAndFines/;
use C4::Utils::DataTables;
use Koha::DateUtils;
use Koha::Patron::Categories;
use Koha::Libraries;

sub search {
    my ($params)     = @_;
    my $searchmember = $params->{searchmember};
    my $firstletter  = $params->{firstletter};
    my $categorycode = $params->{categorycode};
    my $branchcode   = $params->{branchcode};
    my $searchtype       = $params->{searchtype}       || 'contain';
    my $searchfieldstype = $params->{searchfieldstype} || 'standard';
    my $dt_params        = $params->{dt_params};

    my $elastic    = C4::Context->config('elasticsearch');
    my $server     = $elastic->{server};
    my $index_name = $elastic->{index_name};

    my $e = Search::Elasticsearch->new( nodes => $server );

    unless ($searchmember) {
        $searchmember = $dt_params->{sSearch} // '';
    }

    my ( $iTotalRecords, $iTotalDisplayRecords );

    # If branches are independent and user is not superlibrarian
    # The search has to be only on the user branch
    if (C4::Branch::onlymine) {
        my $userenv = C4::Context->userenv;
        $branchcode = $userenv->{'branch'};

    }

    my $query;

    if ( defined $firstletter and $firstletter ne '' ) {
        $query->{surname} = { '^' => [ $firstletter ] }
    }
    if ( defined $categorycode and $categorycode ne '' ) {
        $query->{categorycode} = $categorycode;
    }
    if ( defined $branchcode and $branchcode ne '' ) {
        $query->{branchcode} = $branchcode;
    }

    my $searchfields = {
        standard => 'surname,firstname,othernames,cardnumber,userid',
        surname => 'surname',
        email => 'email,emailpro,B_email',
        borrowernumber => 'borrowernumber',
        userid => 'userid',
        phone => 'phone,phonepro,B_phone,altcontactphone,mobile',
        address => 'streettype,address,address2,city,state,zipcode,country',
        dateofbirth => 'dateofbirth',
        sort1 => 'sort1',
        sort2 => 'sort2',
    };

    # If iDisplayLength == -1, we want to display all patrons
    my %limits;
    if ( !$dt_params->{iDisplayLength} || $dt_params->{iDisplayLength} > -1 ) {
        $limits{from} = $dt_params->{iDisplayStart} || 0;
        $limits{size} = $dt_params->{iDisplayLength} || 20;
    }

    # * is replaced with % for sql
    #$searchmember =~ s/\*/%/g;

    # split into search terms
    my @terms;

    # consider coma as space
    $searchmember =~ s/,/ /g;
    if ( $searchtype eq 'contain' ) {
        @terms = split / /, $searchmember;
    }
    else {
        @terms = ($searchmember);
    }

    my @or;

    if ( $searchtype eq 'start_with' ) {
        for my $searchfield ( split /,/, $searchfields->{$searchfieldstype} ) {
            my $match = { $searchfield => { '^' => \@terms } };
            push( @or, $match );
        }
    }
    else {
        for my $searchfield ( split /,/, $searchfields->{$searchfieldstype} ) {
            my $match = { $searchfield => { '^' => \@terms } };
            push( @or, $match );
        }
    }

    foreach my $term (@terms) {
        next unless $term;


        if ( C4::Context->preference('ExtendedPatronAttributes')
            and $searchmember )
        {
            my $matching_borrowernumbers =
              C4::Members::Attributes::SearchIdMatchingAttribute($searchmember);

            for my $borrowernumber (@$matching_borrowernumbers) {
                push( @or, { borrowernumber => $borrowernumber } );
            }
        }
    }
    $query->{-or} = \@or;
=head

    my $where;
    $where = " WHERE " . join( " AND ", @where_strs ) if @where_strs;
    my $orderby = dt_build_orderby($dt_params);

    my $limit;

    # If iDisplayLength == -1, we want to display all patrons
    if ( !$dt_params->{iDisplayLength} || $dt_params->{iDisplayLength} > -1 ) {

        # In order to avoid sql injection
        $dt_params->{iDisplayStart} =~ s/\D//g
          if defined( $dt_params->{iDisplayStart} );
        $dt_params->{iDisplayLength} =~ s/\D//g
          if defined( $dt_params->{iDisplayLength} );
        $dt_params->{iDisplayStart}  //= 0;
        $dt_params->{iDisplayLength} //= 20;
        $limit =
          "LIMIT $dt_params->{iDisplayStart},$dt_params->{iDisplayLength}";
    }

    my $query = join( " ",
        ( $select  ? $select  : "" ),
        ( $from    ? $from    : "" ),
        ( $where   ? $where   : "" ),
        ( $orderby ? $orderby : "" ),
        ( $limit   ? $limit   : "" ) );
    my $sth = $dbh->prepare($query);
    $sth->execute(@where_args);
    my $patrons = $sth->fetchall_arrayref( {} );

    # Get the iTotalDisplayRecords DataTable variable
    $query =
        "SELECT COUNT(borrowers.borrowernumber) "
      . $from
      . ( $where ? $where : "" );
    $sth = $dbh->prepare($query);
    $sth->execute(@where_args);
    ($iTotalDisplayRecords) = $sth->fetchrow_array;

    # Get the iTotalRecords DataTable variable
    $query = "SELECT COUNT(borrowers.borrowernumber) FROM borrowers";
    $sth   = $dbh->prepare($query);
    $sth->execute;
    ($iTotalRecords) = $sth->fetchrow_array;

    # Get some information on patrons
    foreach my $patron (@$patrons) {
        ( $patron->{overdues}, $patron->{issues}, $patron->{fines} ) =
          GetMemberIssuesAndFines( $patron->{borrowernumber} );
        if ( $patron->{dateexpiry} and $patron->{dateexpiry} ne '0000-00-00' ) {
            $patron->{dateexpiry} = output_pref(
                {
                    dt       => dt_from_string( $patron->{dateexpiry}, 'iso' ),
                    dateonly => 1
                }
            );
        }
        else {
            $patron->{dateexpiry} = '';
        }
        $patron->{fines} = sprintf( "%.2f", $patron->{fines} || 0 );
    }
=cut

    my $sb = ElasticSearch::SearchBuilder->new();
    my $es_query = $sb->query($query);
    warn "QUERY: " . Data::Dumper::Dumper( $query );
    warn "ES QUERY: " . Data::Dumper::Dumper( $es_query );

    my $final_query = {
        index => $index_name . '_patrons',
        body  => {
            %limits,
            %$es_query,
        }
    };

    my $results = $e->search( $final_query  );

    my $total = $results->{hits}->{total};

    my $hits = $results->{hits}->{hits};

    my @patrons = map { $_->{_source} } @$hits;

    my $patrons = \@patrons;


    $iTotalRecords        = $total;
    $iTotalDisplayRecords = $total;

    return {
        iTotalRecords        => $iTotalRecords,
        iTotalDisplayRecords => $iTotalDisplayRecords,
        patrons              => $patrons,
    };
}

sub index {
    my ($patron) = @_;

    my $elastic    = C4::Context->config('elasticsearch');
    my $server     = $elastic->{server};
    my $index_name = $elastic->{index_name};

    my $e = Search::Elasticsearch->new( nodes => $server );

    my $p = $patron->unblessed();

    ( $p->{overdues}, $p->{issues}, $p->{fines} ) =
      GetMemberIssuesAndFines( $patron->{borrowernumber} );
    $p->{fines} = sprintf( "%.2f", $p->{fines} || 0 );

    my $patron_category = Koha::Patron::Categories->find( $p->{categorycode} );
    $p->{category_description} = $patron_category->description;
    $p->{category_type} = $patron_category->category_type;

    my $library = Koha::Libraries->find( $patron->branchcode );
    $p->{branchname} = $library->branchname;

    my $result = $e->index(
        index => $index_name . '_patrons',
        type  => 'patron',
        id    => $patron->id,
        body  => to_json($p),
    );

    return $result;
}

1;
__END__

=head1 NAME

C4::Utils::DataTables::Members - module for using DataTables with patrons

=head1 SYNOPSIS

This module provides (one for the moment) routines used by the patrons search

=head2 FUNCTIONS

=head3 search

    my $dt_infos = C4::Utils::DataTables::Members->search($params);

$params is a hashref with some keys:

=over 4

=item searchmember

  String to search in the borrowers sql table

=item firstletter

  Introduced to contain 1 letter but can contain more.
  The search will done on the borrowers.surname field

=item categorycode

  Search patrons with this categorycode

=item branchcode

  Search patrons with this branchcode

=item searchtype

  Can be 'contain' or 'start_with' (default value). Used for the searchmember parameter.

=item searchfieldstype

  Can be 'standard' (default value), 'email', 'borrowernumber', 'phone', 'address' or 'dateofbirth', 'sort1', 'sort2'

=item dt_params

  Is the reference of C4::Utils::DataTables::dt_get_params($input);

=cut

=back

=head1 LICENSE

This file is part of Koha.

Copyright 2013 BibLibre

Koha is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Koha is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Koha; if not, see <http://www.gnu.org/licenses>.
