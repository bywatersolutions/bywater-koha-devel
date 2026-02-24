#!/usr/bin/perl

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
use Test::MockModule;
use Test::More tests => 6;
use Test::Exception;

BEGIN { use_ok('Koha::ContentSecurityPolicy') }

use C4::Context;
use Koha::Cache::Memory::Lite;

use t::lib::Mocks;

my $conf_csp_section = 'content_security_policy';

subtest 'is_enabled() tests' => sub {

    plan tests => 4;

    foreach my $interface ( 'opac', 'intranet' ) {
        subtest "interface $interface" => sub {
            t::lib::Mocks::mock_config( $conf_csp_section, {} );
            C4::Context->interface($interface);

            my $csp = Koha::ContentSecurityPolicy->new;

            is( $csp->is_enabled, 0, 'CSP is not enabled when koha-conf.xml has not set the entire section' );

            t::lib::Mocks::mock_config(
                $conf_csp_section,
                { $interface => { csp_mode => '', csp_header_value => 'test' } }
            );
            is( $csp->is_enabled, 0, 'CSP is not enabled when csp_mode is empty' );

            t::lib::Mocks::mock_config(
                $conf_csp_section,
                { $interface => { csp_mode => 'wrong', csp_header_value => 'test' } }
            );
            is( $csp->is_enabled, 0, 'CSP is not enabled when csp_mode has not got a valid csp_header_value' );

            t::lib::Mocks::mock_config(
                $conf_csp_section,
                { $interface => { csp_mode => 'report-only', csp_header_value => 'test' } }
            );
            is( $csp->is_enabled, 1, 'CSP is enabled when csp_mode is report-only' );

            t::lib::Mocks::mock_config(
                $conf_csp_section,
                { $interface => { csp_mode => 'enabled', csp_header_value => 'test' } }
            );
            is( $csp->is_enabled, 1, 'CSP is enabled when csp_mode is enabled' );

            t::lib::Mocks::mock_config(
                $conf_csp_section,
                {
                    $interface => {
                        csp_mode => 'enabled', csp_header_value => 'test',
                    }
                }
            );
        };
    }

    t::lib::Mocks::mock_config(
        $conf_csp_section, { opac => { csp_mode => 'enabled', csp_header_value => 'test' } },
        intranet => { csp_mode => '', csp_header_value => 'test' }
    );
    C4::Context->interface('intranet');
    my $csp = Koha::ContentSecurityPolicy->new;
    is( $csp->is_enabled, 0, 'CSP is disabled when other interface is enabled, but not this one' );
    is( $csp->is_enabled( { interface => 'opac' } ), 1, 'CSP is enabled when explicitly defining interface' );
};

subtest 'header_name tests' => sub {
    plan tests => 6;

    t::lib::Mocks::mock_config( $conf_csp_section, {} );
    C4::Context->interface('opac');

    my $csp = Koha::ContentSecurityPolicy->new;

    throws_ok { $csp->header_name } 'Koha::Exceptions::Config::MissingEntry', 'Exception thrown when missing csp_mode';

    t::lib::Mocks::mock_config( $conf_csp_section, { opac => {} } );
    throws_ok { $csp->header_name } 'Koha::Exceptions::Config::MissingEntry', 'Exception thrown when missing csp_mode';

    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_mode => '' } } );
    throws_ok { $csp->header_name } 'Koha::Exceptions::Config::MissingEntry', 'Exception thrown when missing csp_mode';
    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_mode => 'invalid' } } );
    throws_ok { $csp->header_name } 'Koha::Exceptions::Config::MissingEntry', 'Exception thrown when invalid csp_mode';

    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_mode => 'report-only' } } );
    is(
        $csp->header_name, 'Content-Security-Policy-Report-Only',
        'report-only => Content-Security-Policy-Report-Only'
    );
    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_mode => 'enabled' } } );
    is( $csp->header_name, 'Content-Security-Policy', 'enabled => Content-Security-Policy' );
};

subtest 'header_value tests' => sub {
    plan tests => 4;

    t::lib::Mocks::mock_config( $conf_csp_section, {} );
    C4::Context->interface('opac');

    my $csp = Koha::ContentSecurityPolicy->new;

    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_header_value => '' } } );
    like(
        $csp->header_value, qr/^default-src 'self';.*_CSP_NONCE_/,
        'csp_header_value is retrieved from ContentSecurityPolicy.pm'
    );

    t::lib::Mocks::mock_config( $conf_csp_section, { opac => { csp_header_value => 'some value' } } );
    is( $csp->header_value, 'some value', 'csp_header_value is retrieved from koha-conf.xml' );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_header_value => 'begin nonce-_CSP_NONCE_ end' } }
    );
    $csp->set_nonce('cached value');
    is( $csp->header_value, 'begin nonce-cached value end', 'Cached csp_header_value' );

    $csp = Koha::ContentSecurityPolicy->new( { nonce => 'forced value' } );
    is( $csp->header_value, 'begin nonce-forced value end', 'Forced csp_header_value' );
};

subtest 'nonce tests' => sub {
    plan tests => 5;

    t::lib::Mocks::mock_config( $conf_csp_section, {} );
    C4::Context->interface('opac');

    my $csp = Koha::ContentSecurityPolicy->new;

    $csp = Koha::ContentSecurityPolicy->new( { nonce => 'forced value' } );
    is( $csp->get_nonce, 'forced value', 'nonce is not re-generated as it was passed to new()' );

    $csp = Koha::ContentSecurityPolicy->new( { nonce => 'forced value' } );
    is( $csp->get_nonce, 'forced value', 'nonce is not re-generated as was cached in memory' );

    $csp->set_nonce();

    $csp = Koha::ContentSecurityPolicy->new();
    my $nonce = $csp->get_nonce;
    like( $nonce, qr/\w{22}/, 'nonce is a random string of 22 characters (128+ bits entropy)' );
    is( $nonce, $csp->get_nonce, 're-calling nonce() returns the same randomly generated cached value' );

    $csp->set_nonce('cached value');
    is( $csp->get_nonce, 'cached value', 'nonce is not re-generated as it was previously cached' );
};

1;
