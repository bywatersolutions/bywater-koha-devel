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
use Test::More tests => 3;
use Test::Warn;

use File::Basename qw(dirname);
use HTTP::Request::Common;
use Plack::Builder;
use Plack::Util;
use Plack::Test;

use C4::Templates;

use t::lib::Mocks;

use_ok("Koha::Middleware::ContentSecurityPolicy");

my $conf_csp_section = 'content_security_policy';

subtest 'test Content-Security-Policy header' => sub {
    plan tests => 3;

    my $csp_header_value =
        "default-src 'self'; script-src 'self' 'nonce-_CSP_NONCE_'; style-src 'self' 'nonce-_CSP_NONCE_'; img-src 'self' data:; font-src 'self'; object-src 'none'";

    t::lib::Mocks::mock_config(
        $conf_csp_section,
        { opac => { csp_mode => 'enabled', csp_header_value => $csp_header_value } }
    );

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
};
