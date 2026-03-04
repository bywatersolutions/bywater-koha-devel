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

use Modern::Perl;
use Test::NoWarnings;
use Test::More tests => 6;

use HTTP::Request::Common;
use Plack::App::CGIBin;
use Plack::Builder;
use Plack::Test;

use Koha::Database;

use t::lib::Mocks;

use_ok("Koha::Middleware::ContentSecurityPolicy");

my $conf_csp_section = 'content_security_policy';

my $schema = Koha::Database->schema;

subtest 'test Content-Security-Policy header in a minimal environment' => sub {
    plan tests => 3;

    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

    my $original_opachtdocs = C4::Context->config('opachtdocs');
    t::lib::Mocks::mock_config( 'opachtdocs', C4::Context->config('intranetdir') . '/t/mock_templates/opac-tmpl' );

    my $env = {};
    my $app = sub {
        require Koha::Plugins;    # this should probably be "use Koha::Plugins;" in C4::Templates instead
        my $template = C4::Templates::gettemplate( 'opac-csp.tt', 'opac' );
        my $resp     = [
            200,
            [
                'Content-Type',
                'text/plain',
                'Content-Length',
                12
            ],
            [ $template->output ]
        ];
        return $resp;
    };

    $app = builder {
        enable "+Koha::Middleware::ContentSecurityPolicy";
        $app;
    };

    my $test                      = Plack::Test->create($app);
    my $res                       = $test->request( GET "/" );
    my $test_nonce                = Koha::ContentSecurityPolicy->new->get_nonce();
    my $expected_csp_header_value = $csp_header_value;
    $expected_csp_header_value =~ s/_CSP_NONCE_/$test_nonce/g;
    is(
        $res->header('content-security-policy'), $expected_csp_header_value,
        "Response contains Content-Security-Policy header with the expected value"
    );
    is(
        $res->content, '<script nonce="' . $test_nonce . '">' . "\n" . '</script>' . "\n",
        "Response contains generated nonce in the body"
    );

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => '', csp_header_value => $csp_header_value } }
    );

    $res = $test->request( GET "/" );
    is(
        $res->header('content-security-policy'), undef,
        "Response does not contain Content-Security-Policy header when it is disabled in koha-conf.xml"
    );

    # cleanup
    t::lib::Mocks::mock_config( 'opachtdocs', $original_opachtdocs );

};

subtest 'test CSP in OPAC' => sub {
    plan tests => 5;

    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_preference( 'OpacPublic', 1 );
    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

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
    my $test_nonce                = Koha::ContentSecurityPolicy->new->get_nonce();
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

    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

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
    my $test_nonce                = Koha::ContentSecurityPolicy->new->get_nonce();
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

    $res                       = $test->request( GET "/intranet/mainpage.pl" );
    $test_nonce                = Koha::ContentSecurityPolicy->new->get_nonce();
    $expected_csp_header_value = $csp_header_value;
    $expected_csp_header_value =~ s/_CSP_NONCE_/$test_nonce/g;
    is(
        $res->header('content-security-policy'), $expected_csp_header_value,
        "Response contains Content-Security-Policy header when it is enabled in koha-conf.xml"
    );

    like( $res->content, qr/<body id="main_auth"/, 'mainpage.pl looks okay' );
};

subtest 'test Reporting-Endpoints for CSP violation reports' => sub {
    plan tests => 1;

    my $test_nonce = 'TEST_NONCE';
    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_preference( 'SessionStorage', 'tmp' );

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'OpacPublic', 1 );
    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

    # Set nonce
    Koha::ContentSecurityPolicy->new->set_nonce($test_nonce);

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
    like(
        $res->header('reporting-endpoints'), qr/^csp-violations="\/api\/v1\/public\/csp-reports"$/,
        "Response contains Reporting-Endpoints header with the expected value"
    );

    $schema->storage->txn_rollback;
};
