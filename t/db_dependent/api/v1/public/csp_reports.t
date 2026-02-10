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

use Carp qw( carp );
use Log::Log4perl;

use t::lib::Mocks;

use Koha::Database;

my $schema = Koha::Database->new->schema;
my $t      = Test::Mojo->new('Koha::REST::V1');

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'add() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    foreach my $csp_report_type ( 'report-uri', 'report-to' ) {
        subtest "Test $csp_report_type" => sub {
            plan tests => 15;
            my $content_type = $csp_report_type eq 'report-to' ? 'application/csp-report' : 'application/reports+json';

            # Test with standard CSP report-uri format
            my $csp_report = {
                'csp-report' => {
                    'document-uri'        => 'https://library.example.org/cgi-bin/koha/opac-main.pl',
                    'referrer'            => '',
                    'violated-directive'  => "script-src",
                    'effective-directive' => 'script-src',
                    'original-policy'     => "default-src 'self'; script-src 'self' 'nonce-abc123'",
                    'disposition'         => 'enforce',
                    'blocked-uri'         => 'inline',
                    'line-number'         => 42,
                    'column-number'       => 10,
                    'source-file'         => 'https://library.example.org/cgi-bin/koah/opac-main.pl',
                    'status-code'         => 200,
                }
            };
            if ( $csp_report_type eq 'report-to' ) {
                $csp_report->{'body'}       = delete $csp_report->{'csp-report'};
                $csp_report->{'age'}        = 1;
                $csp_report->{'type'}       = 'csp-violation';
                $csp_report->{'url'}        = 'https://library.example.org/cgi-bin/koha/opac-main.pl';
                $csp_report->{'user_agent'} = 'Test::Mojo';
            }

            my $csp_report_body_key = $csp_report_type eq 'report-uri' ? 'csp-report' : 'body';

            $csp_report->{$csp_report_body_key}->{'line-number'} = 99999999999999999;

            # Too large integers should be rejected
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is( 400, 'CSP report rejected (400) because of line-number exceeding maximum value' );

            $csp_report->{$csp_report_body_key}->{'line-number'} = -1;

            # Too small integers should be rejected
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is( 400, 'CSP report rejected (400) because of line-number not reaching minimum value' );
            $csp_report->{$csp_report_body_key}->{'line-number'} = 42;

            $csp_report->{$csp_report_body_key}->{'disposition'} = 'this is not okay';

            # Enum values should be confirmed
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is(
                400,
                'CSP report rejected (400) because of disposition is not either "enforce" nor "report"'
                );
            $csp_report->{$csp_report_body_key}->{'disposition'} = 'enforce';

            $csp_report->{$csp_report_body_key}->{'script-sample'} =
                'this is way too long script sample. a maximum of only 40 characters is allowed';

            # Too long strings should be rejected
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is( 400, 'CSP report rejected (400) because of script-sample exceeding maximum length' );
            $csp_report->{$csp_report_body_key}->{'script-sample'} = 'console.log("hi");';

            # Anonymous request should work (browsers send these without auth)
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is( 204, 'CSP report accepted' );

            # Test with application/json content type (also valid)
            $t->post_ok( '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                ->status_is( 204, 'CSP report accepted with application/json content type' );

            # Test with minimal report
            my $minimal_report = {
                'csp-report' => {
                    'document-uri'       => 'https://library.example.org/',
                    'violated-directive' => 'script-src',
                    'blocked-uri'        => 'https://evil.example.com/script.js',
                }
            };
            if ( $csp_report_type eq 'report-to' ) {
                $minimal_report->{'body'}       = delete $minimal_report->{'csp-report'};
                $minimal_report->{'age'}        = 1;
                $minimal_report->{'type'}       = 'csp-violation';
                $minimal_report->{'url'}        = 'https://library.example.org/cgi-bin/koha/opac-main.pl';
                $minimal_report->{'user_agent'} = 'Test::Mojo';
            }

            $t->post_ok(
                '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $minimal_report )
                ->status_is( 204, 'Minimal CSP report accepted' );

            subtest 'make sure log entries are being written' => sub {
                plan tests => 17;

                my $log4perl_conf_file = C4::Context->config('intranetdir') . '/etc/log4perl.conf';
                open my $fh, '<:encoding(UTF-8)', $log4perl_conf_file or do {
                    carp "Cannot read $log4perl_conf_file: $!";
                    return;
                };
                my $log4perl_conf_content = "";
                while (<$fh>) {
                    my $line = $_;
                    next unless $line =~ /^(log4perl.logger.(plack-)?csp)|(log4perl.appender.(PLACK)?CSP)/;
                    $log4perl_conf_content .= "$line";
                }
                close $fh;
                like( $log4perl_conf_content, qr/__LOG_DIR__\/csp-violations\.log/, 'csp-violations.log is defined' );
                like(
                    $log4perl_conf_content, qr/__LOG_DIR__\/plack-csp-violations\.log/,
                    'plack-csp-violations.log is defined'
                );
                like(
                    $log4perl_conf_content, qr/log4perl.appender.CSP=Log::Log4perl::Appender::File/,
                    'CSP: File appender exists'
                );
                like(
                    $log4perl_conf_content, qr/log4perl.appender.PLACKCSP=Log::Log4perl::Appender::File/,
                    'PLACKCSP: File appender exists'
                );
                $log4perl_conf_content =~ s/Log::Log4perl::Appender::File/Log::Log4perl::Appender::TestBuffer/g;
                Log::Log4perl::init( \$log4perl_conf_content );
                my $appenders     = Log::Log4perl->appenders;
                my $appender      = Log::Log4perl->appenders->{CSP};
                my $appenderplack = Log::Log4perl->appenders->{PLACKCSP};

                is( $appender->buffer,      '', 'Nothing in log buffer yet' );
                is( $appenderplack->buffer, '', 'Nothing in plack log buffer yet' );

                $t->post_ok(
                    '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                    ->status_is( 204, 'CSP report accepted' );

                my $expected_log_entry = sprintf(
                    "CSP violation: '%s' blocked '%s' on page '%s'%s",
                    $csp_report->{$csp_report_body_key}->{'violated-directive'},
                    $csp_report->{$csp_report_body_key}->{'blocked-uri'},
                    $csp_report->{$csp_report_body_key}->{'document-uri'},
                    ' at '
                        . $csp_report->{$csp_report_body_key}->{'source-file'} . ':'
                        . $csp_report->{$csp_report_body_key}->{'line-number'} . ':'
                        . $csp_report->{$csp_report_body_key}->{'column-number'}
                );

                like(
                    $appender->buffer, qr/$expected_log_entry/
                    ,                  'Log contains expected log entry'
                );
                is( $appenderplack->buffer, '', 'Nothing in plack log buffer yet' );
                $appender->clear();

                $ENV{'plack.is.enabled.for.this.test'} = 1;    # tricking C4::Context->psgi_env
                $t->post_ok(
                    '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                    ->status_is( 204, 'CSP report accepted' );
                like(
                    $appenderplack->buffer, qr/$expected_log_entry/
                    ,                       'Plack log contains expected log entry'
                );
                is( $appender->buffer, '', 'Nothing in log buffer yet' );

                Log::Log4perl::init(
                    \<<"HERE"
log4perl.logger.api = WARN, API
log4perl.appender.API=Log::Log4perl::Appender::TestBuffer
log4perl.appender.API.mode=append
log4perl.appender.API.layout=PatternLayout
log4perl.appender.API.layout.ConversionPattern=[%d] [%p] %m %l%n
log4perl.appender.API.utf8=1
HERE
                );
                $appender = Log::Log4perl->appenders()->{API};
                $t->post_ok(
                    '/api/v1/public/csp-reports' => { 'Content-Type' => $content_type } => json => $csp_report )
                    ->status_is( 204, 'CSP report returns 204 even when no CSP loggers are defined' );
                is( $appender->buffer, '', 'Nothing in the only defined log buffer, because it is unrelated to CSP' );

                # clear buffers
                $appender->clear();
                $appenderplack->clear();
                delete $ENV{'plack.is.enabled.for.this.test'};
            };
        };
    }

    $schema->storage->txn_rollback;
};

1;
