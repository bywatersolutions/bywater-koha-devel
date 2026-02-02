#!/usr/bin/env perl

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

use Test::NoWarnings;
use Test::More tests => 2;
use Test::Mojo;
use Test::Warn;

use t::lib::Mocks;

use Koha::Database;

my $schema = Koha::Database->new->schema;
my $t      = Test::Mojo->new('Koha::REST::V1');

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'add() tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    # Test with standard CSP report format
    my $csp_report = {
        'csp-report' => {
            'document-uri'        => 'https://library.example.org/cgi-bin/koha/opac-main.pl',
            'referrer'            => '',
            'violated-directive'  => "script-src 'self' 'nonce-abc123'",
            'effective-directive' => 'script-src',
            'original-policy'     => "default-src 'self'; script-src 'self' 'nonce-abc123'",
            'disposition'         => 'enforce',
            'blocked-uri'         => 'inline',
            'line-number'         => 42,
            'column-number'       => 10,
            'source-file'         => 'https://library.example.org/cgi-bin/koha/opac-main.pl',
            'status-code'         => 200,
        }
    };

    # Anonymous request should work (browsers send these without auth)
    $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => 'application/csp-report' } => json => $csp_report )
        ->status_is( 204, 'CSP report accepted' );

    # Test with application/json content type (also valid)
    $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => 'application/json' } => json => $csp_report )
        ->status_is( 204, 'CSP report accepted with application/json content type' );

    # Test with minimal report
    my $minimal_report = {
        'csp-report' => {
            'document-uri'       => 'https://library.example.org/',
            'violated-directive' => 'script-src',
            'blocked-uri'        => 'https://evil.example.com/script.js',
        }
    };

    $t->post_ok( '/api/v1/public/csp-reports' => json => $minimal_report )
        ->status_is( 204, 'Minimal CSP report accepted' );

    $schema->storage->txn_rollback;
};

1;
