package Koha::Patron::Discharge;

use Modern::Perl;
use CGI;
use File::Temp qw( tmpnam );
use IPC::Cmd;
use Carp qw( carp );

use C4::Templates qw ( gettemplate );
use C4::Letters qw( GetPreparedLetter );

use Koha::Database;
use Koha::DateUtils qw( dt_from_string output_pref );
use Koha::Patrons;
use Koha::Patron::Debarments qw( AddDebarment );

sub count {
    my ($params) = @_;
    my $values = {};

    if( $params->{borrowernumber} ) {
        $values->{borrower} = $params->{borrowernumber};
    }
    if( $params->{pending} ) {
        $values->{needed} = { '!=', undef };
        $values->{validated} = undef;
    }
    elsif( $params->{validated} ) {
        $values->{validated} = { '!=', undef };
    }

    return search_limited( $values )->count;
}

sub can_be_discharged {
    my ($params) = @_;
    return unless $params->{borrowernumber};

    my $patron = Koha::Patrons->find( $params->{borrowernumber} );
    return unless $patron;

    my $can_be_discharged = 1;
    my $problems          = {};

    my $checkouts = $patron->checkouts->count;
    if ($checkouts) {
        $can_be_discharged = 0;
        $problems->{checkouts} = $checkouts;
    }

    my $debt = $patron->account->outstanding_debits->total_outstanding;
    if ( $debt > 0 ) {
        $can_be_discharged = 0;
        $problems->{debt} = $debt;
    }

    return ( $can_be_discharged, $problems );
}

sub is_discharged {
    my ($params) = @_;
    return unless $params->{borrowernumber};
    my $borrowernumber = $params->{borrowernumber};

    my $restricted = Koha::Patrons->find($borrowernumber)->is_debarred;
    my @validated  = get_validated( { borrowernumber => $borrowernumber } );

    if ( $restricted && @validated ) {
        return 1;
    } else {
        return 0;
    }
}

sub request {
    my ($params) = @_;
    my $borrowernumber = $params->{borrowernumber};
    return unless $borrowernumber;
    my ($can) = can_be_discharged( { borrowernumber => $borrowernumber } );
    return unless $can;

    my $rs = Koha::Database->new->schema->resultset('Discharge');
    return $rs->create(
        {
            borrower => $borrowernumber,
            needed   => dt_from_string,
        }
    );
}

sub discharge {
    my ($params) = @_;
    my $borrowernumber = $params->{borrowernumber};

    my ( $can ) = can_be_discharged({ borrowernumber => $borrowernumber });
    return unless $borrowernumber and $can;

    # Cancel reserves
    my $patron = Koha::Patrons->find( $borrowernumber );
    my $holds = $patron->holds;
    while ( my $hold = $holds->next ) {
        $hold->cancel;
    }

    # Debar the member
    Koha::Patron::Debarments::AddDebarment({
        borrowernumber => $borrowernumber,
        type           => 'DISCHARGE',
    });

    # Generate the discharge
    my $rs = Koha::Database->new->schema->resultset('Discharge');
    my $discharge = $rs->search({ borrower => $borrowernumber }, { order_by => { -desc => 'needed' }, rows => 1 });
    if( $discharge->count > 0 ) {
        $discharge->update({ validated => dt_from_string });
    }
    else {
        $rs->create({
            borrower  => $borrowernumber,
            validated => dt_from_string,
        });
    }
}

sub generate_as_pdf {
    my ($params) = @_;
    return unless $params->{borrowernumber};

    my $patron = Koha::Patrons->find( $params->{borrowernumber} );
    my $letter = C4::Letters::GetPreparedLetter(
        module      => 'members',
        letter_code => 'DISCHARGE',
        lang        => $patron->lang,
        tables      => { borrowers => $params->{borrowernumber}, branches => $params->{'branchcode'}, },
    );

    my $today = output_pref( dt_from_string() );
    $letter->{'title'}   =~ s/<<today>>/$today/g;
    $letter->{'content'} =~ s/<<today>>/$today/g;

    my $tmpl = C4::Templates::gettemplate('batch/print-notices.tt', 'intranet', CGI->new);
    $tmpl->param(
        stylesheet => C4::Context->preference("NoticeCSS"),
        today      => $today,
        messages   => [$letter],
    );

    my $html_path = tmpnam() . '.html';
    my $pdf_path = tmpnam() . '.pdf';
    my $html_content = $tmpl->output;

    # export to HTML
    open my $html_fh, '>:encoding(utf8)', $html_path;
    say $html_fh $html_content;
    close $html_fh;

    if ( IPC::Cmd::can_run('weasyprint') ) {
        my( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
            IPC::Cmd::run( command => "weasyprint $html_path $pdf_path", verbose => 0 );

        map {warn $_} @$stderr_buf
          if $stderr_buf and scalar @$stderr_buf;

        unless ( $success ) {
            warn $error_message;
            $pdf_path = undef;
        }
    }
    else {
        warn "weasyprint not found!";
        $pdf_path = undef;
    }

    return $pdf_path;
}

sub get_pendings {
    my ($params)       = @_;
    my $branchcode     = $params->{branchcode};
    my $borrowernumber = $params->{borrowernumber};

    my $cond = {
        'me.needed'    => { '!=', undef },
        'me.validated' => undef,
        ( defined $borrowernumber ? ( 'me.borrower' => $borrowernumber ) : () ),
        ( defined $branchcode ? ( 'borrower.branchcode' => $branchcode ) : () ),
    };

    return search_limited( $cond );
}

sub get_validated {
    my ($params)       = @_;
    my $branchcode     = $params->{branchcode};
    my $borrowernumber = $params->{borrowernumber};

    my $cond = {
        'me.validated' => { '!=', undef },
        ( defined $borrowernumber ? ( 'me.borrower' => $borrowernumber ) : () ),
        ( defined $branchcode ? ( 'borrower.branchcode' => $branchcode ) : () ),
    };

    return search_limited( $cond );
}

# TODO This module should be based on Koha::Object[s]
sub search_limited {
    my ( $params, $attributes ) = @_;
    my $userenv = C4::Context->userenv;
    my @restricted_branchcodes;
    if ( $userenv and $userenv->{number} ) {
        my $logged_in_user = Koha::Patrons->find( $userenv->{number} );
        @restricted_branchcodes = $logged_in_user->libraries_where_can_see_patrons;
    }
    $params->{'borrower.branchcode'} = { -in => \@restricted_branchcodes } if @restricted_branchcodes;
    $attributes->{join} = 'borrower';

    my $rs = Koha::Database->new->schema->resultset('Discharge');
    return $rs->search( $params, { join => 'borrower' } );
}

1;
