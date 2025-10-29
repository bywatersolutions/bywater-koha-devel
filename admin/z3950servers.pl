#!/usr/bin/perl

# Copyright 2002 paul.poulain@free.fr
# Copyright 2014 Rijksmuseum
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

# This script is used to maintain the Z3950 servers table.
# Parameter $op is operation: list, new, edit, add_validated, delete_confirmed.
# add_validated saves a validated record and goes to list view.
# delete_confirmed deletes a record and goes to list view.

use Modern::Perl;
use CGI qw ( -utf8 );
use C4::Context;
use C4::Auth   qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use Koha::Z3950Servers;
use Try::Tiny qw( catch try );

# Initialize CGI, template

my $input       = CGI->new;
my $op          = $input->param('op')   || 'list';
my $id          = $input->param('id')   || 0;
my $type        = $input->param('type') || '';
my $searchfield = '';

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "admin/z3950servers.tt",
        query         => $input,
        type          => "intranet",
        flagsrequired => { parameters => 'manage_search_targets' },
    }
);

# Main code
# First process a confirmed delete, or save a validated record

if ( $op eq 'cud-delete_confirmed' && $id ) {
    my $server = Koha::Z3950Servers->find($id);
    if ($server) {
        $server->delete;
        $template->param( msg_deleted => 1, msg_add => $server->servername );
    } else {
        $template->param( msg_notfound => 1, msg_add => $id );
    }
    $id = 0;
} elsif ( $op eq 'cud-add_validated' ) {
    my @fields = qw/host port db userid password rank syntax encoding timeout
        recordtype checked servername servertype sru_options sru_fields attributes
        add_xslt/;
    my $formdata = _form_data_hashref( $input, \@fields );
    my @branches = grep { $_ ne q{} } $input->multi_param('branches');

    if ($id) {
        my $server = Koha::Z3950Servers->find($id);
        if ($server) {
            try {
                $server->set($formdata)->store;
                $server->replace_library_limits( \@branches );
                $template->param( msg_updated => 1, msg_add => $formdata->{servername} );
            } catch {
                $template->param( msg_error => 1, msg_add => $formdata->{servername} );
            };
        } else {
            $template->param( msg_notfound => 1, msg_add => $id );
        }
        $id = 0;
    } else {
        try {
            my $server = Koha::Z3950Server->new($formdata)->store;
            $server->replace_library_limits( \@branches );
            $template->param( msg_added => 1, msg_add => $formdata->{servername} );
        } catch {
            $template->param( msg_error => 1, msg_add => $formdata->{servername} );
        };
    }
} elsif ( $op eq 'search' ) {

    #use searchfield only in remaining operations
    $searchfield = $input->param('searchfield') || '';
}

# Now list multiple records, or edit one record

if ( $op eq 'add_form' ) {
    my $server;

    if ($id) {
        $server = Koha::Z3950Servers->find($id);
        if ($server) {

            # Cloning record - remove id
            $server = $server->unblessed;
            delete $server->{id};
        }
    }

    $template->param(
        server => $server,
        op     => $op,
        type   => lc $type
    );
} elsif ( $op eq 'edit_form' ) {
    my $server = Koha::Z3950Servers->find($id);
    $template->param(
        server => $server,
        op     => $op,
        type   => ''
    );
} else {    # search
    my $data = Koha::Z3950Servers->search(
        $id ? { id => $id } : { servername => { like => $searchfield . '%' } },
    );
    $template->param(
        loop => $data, searchfield => $searchfield, id => $id,
        op   => 'list'
    );
}
output_html_with_http_headers $input, $cookie, $template->output;

# End of main code

sub _form_data_hashref {
    my ( $input, $fieldref ) = @_;
    return { map { ( $_ => scalar $input->param($_) // '' ) } @$fieldref };
}
