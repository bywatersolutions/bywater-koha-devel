#!/usr/bin/perl

#
# Copyright 2025 Hypernova Oy
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

use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 4;

use HTTP::Request::Common;
use Plack::App::CGIBin;
use Plack::Builder;
use Plack::Test;

use t::lib::Mocks;

use_ok("Koha::Middleware::ContentSecurityPolicy");

my $conf_csp_section = 'content_security_policy';

subtest 'test CSP in OPAC' => sub {
    plan tests => 5;

    my $test_nonce = 'TEST_NONCE';
    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_preference( 'OpacPublic', 1 );
    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

    # Set nonce
    Koha::ContentSecurityPolicy->new->nonce($test_nonce);

    my $env  = {};
    my $home = $ENV{KOHA_HOME};
    my $app  = Plack::App::CGIBin->new( root => $ENV{GIT_INSTALL} ? "$home/opac" : "$home/opac/cgi-bin/opac" )->to_app;

    $app = builder {
        mount '/opac' => builder {
            enable "+Koha::Middleware::ContentSecurityPolicy";
            $app;
        };
    };

    my $test                      = Plack::Test->create($app);
    my $res                       = $test->request( GET "/opac/opac-main.pl" );
    my $expected_csp_header_value = $csp_header_value;
    $expected_csp_header_value =~ s/_CSP_NONCE_/$test_nonce/g;
    is(
        $res->header('content-security-policy'), $expected_csp_header_value,
        "Response contains Content-Security-Policy header with the expected value"
    );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => '', csp_header_value => $csp_header_value } }
    );

    $res = $test->request( GET "/opac/opac-main.pl" );
    is(
        $res->header('content-security-policy'), undef,
        "Response does not contain Content-Security-Policy header when it is disabled in koha-conf.xml"
    );

    like( $res->content, qr/<body ID="opac-main"/, 'opac-main.pl looks okay' );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        {}
    );

    $res = $test->request( GET "/opac/opac-main.pl" );
    is(
        $res->header('content-security-policy'), undef,
        "Response does not contain Content-Security-Policy header when it has not been defined in koha-conf.xml"
    );

    like( $res->content, qr/<body ID="opac-main"/, 'opac-main.pl looks okay' );
};

subtest 'test CSP in staff client' => sub {
    plan tests => 5;

    my $test_nonce = 'TEST_NONCE';
    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

    # Set nonce
    Koha::ContentSecurityPolicy->new->nonce($test_nonce);

    my $env  = {};
    my $home = $ENV{KOHA_HOME};
    my $app  = Plack::App::CGIBin->new( root => $ENV{GIT_INSTALL} ? $home : "$home/intranet/cgi-bin/" )->to_app;

    $app = builder {
        mount '/intranet' => builder {
            enable "+Koha::Middleware::ContentSecurityPolicy";
            $app;
        };
    };

    my $test                      = Plack::Test->create($app);
    my $res                       = $test->request( GET "/intranet/mainpage.pl" );
    my $expected_csp_header_value = $csp_header_value;
    $expected_csp_header_value =~ s/_CSP_NONCE_/$test_nonce/g;
    is(
        $res->header('content-security-policy'), undef,
        "Response does not Content-Security-Policy header when it has not been defined in koha-conf.xml"
    );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        {
            intranet => {
                csp_mode => '', csp_header_value => $csp_header_value,
            }
        }
    );

    $res = $test->request( GET "/intranet/mainpage.pl" );
    is(
        $res->header('content-security-policy'), undef,
        "Response does not contain Content-Security-Policy header when it is explicitly disabled in koha-conf.xml"
    );

    like( $res->content, qr/<body id="main_auth"/, 'mainpage.pl looks okay' );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { intranet => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

    $res = $test->request( GET "/intranet/mainpage.pl" );
    is(
        $res->header('content-security-policy'), $expected_csp_header_value,
        "Response contains Content-Security-Policy header when it is enabled in koha-conf.xml"
    );

    like( $res->content, qr/<body id="main_auth"/, 'mainpage.pl looks okay' );
};
