package Koha::REST::V1::CSPReports;

# Copyright 2025 Koha Development Team
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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::ContentSecurityPolicy;
use Koha::Logger;

=head1 NAME

Koha::REST::V1::CSPReports - Controller for Content-Security-Policy violation reports

=head1 DESCRIPTION

This controller provides an endpoint to receive CSP violation reports from browsers.
Reports are logged using Koha's logging system for analysis and debugging.

=head1 METHODS

=head2 add

Receives a CSP violation report and logs it.

Browsers send CSP violations as JSON POST requests when a Content-Security-Policy
is violated. This endpoint logs those reports for administrator review.

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    # Return HTTP 204 if CSP is disabled.
    # We could return 4xx, but clients do not need to be aware of the configured
    # status of this endpoint
    my $csp = Koha::ContentSecurityPolicy->new;
    return $c->render(
        status  => 204,
        openapi => undef
    ) if !$csp->is_enabled( { interface => 'opac' } ) && !$csp->is_enabled( { interface => 'intranet' } );

    my $logger = Koha::Logger->get( { interface => 'csp' } );

    my @reports           = ();
    my $reports_from_json = $c->req->json;
    if ( ref $reports_from_json eq 'ARRAY' ) {

        #FIXME: We could just take the top X number of reports...
        push( @reports, @$reports_from_json );
    } elsif ( ref $reports_from_json eq 'HASH' ) {
        push( @reports, $reports_from_json );
    }

    # CSP reports come wrapped in a 'csp-report' key
    foreach my $report (@reports) {
        my $csp_report = $report->{'csp-report'} // $report->{body};

        # Extract key fields for logging
        my $document_uri = $csp_report->{'documentURL'} // $csp_report->{'document-uri'} // 'unknown';
        my $violated_dir = $csp_report->{'effectiveDirective'} // $csp_report->{'effective-directive'}
            // $csp_report->{'violated-directive'} // 'unknown';
        my $blocked_uri   = $csp_report->{'blockedURL'}   // $csp_report->{'blocked-uri'}   // 'unknown';
        my $source_file   = $csp_report->{'sourceFile'}   // $csp_report->{'source-file'}   // '';
        my $line_number   = $csp_report->{'lineNumber'}   // $csp_report->{'line-number'}   // '';
        my $column_number = $csp_report->{'columnNumber'} // $csp_report->{'column-number'} // '';

        # Build location string if available
        my $location = '';
        if ($source_file) {
            $location = " at $source_file";
            $location .= ":$line_number"   if $line_number;
            $location .= ":$column_number" if $column_number;
        }

        $logger->warn(
            sprintf(
                "CSP violation: '%s' blocked '%s' on page '%s'%s",
                $violated_dir,
                $blocked_uri,
                $document_uri,
                $location
            )
        );

        # Log full report at debug level for detailed analysis
        if ( $logger->is_debug ) {
            require JSON;
            $logger->debug( "CSP report details: " . JSON::encode_json($csp_report) );
        }
    }

    return $c->render(
        status  => 204,
        openapi => undef
    );
}

1;
