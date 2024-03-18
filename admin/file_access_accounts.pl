#!/usr/bin/perl

# Copyright 2011,2014 Mark Gavillet & PTFS Europe Ltd
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use CGI;

use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );

use Koha::Database;
use Koha::Encryption;
use Koha::Plugins;
use Koha::File::Access::Accounts;

our $input  = CGI->new();
our $schema = Koha::Database->new()->schema();

our ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => 'admin/file_access_accounts.tt',
        query         => $input,
        type          => 'intranet',
        flagsrequired => { parameters => '*' },
    }
);

my $crypt = Koha::Encryption->new;

my $op = $input->param('op') || 'show_accounts_list';

if ( $op eq 'create_edit_account' ) {
    my $id      = scalar $input->param('id');
    my $account = $id ? Koha::File::Access::Accounts->find($id) : undef;
    $account->password( $crypt->decrypt_hex( $account->password ) ) if $account;
    $template->param(
        create_edit_account => 1,
        account             => $account,
    );
} elsif ( $op eq 'delete_confirm' ) {
    my $id      = scalar $input->param('id');
    my $account = Koha::File::Access::Accounts->find($id);
    $template->param( delete_confirm => 1, account => $account );
} else {
    my $show_accounts_list = 0;

    if ( $op eq 'cud-save' ) {

        my $original_code = scalar $input->param('original_code');
        my $code          = scalar $input->param('code');
        my $description   = scalar $input->param('description');
        my $transport     = scalar $input->param('transport');
        my $host          = scalar $input->param('host');
        my $username      = scalar $input->param('username');
        my $password      = scalar $input->param('password');
        my $debug         = scalar $input->param('debug');

        my $encrypted_password = $crypt->encrypt_hex($password);
        my $fields             = {
            code        => $code,
            description => $description,
            transport   => $transport,
            host        => $host,
            username    => $username,
            password    => $encrypted_password,
            debug       => $debug ? 1 : 0,
        };

        my $account = $original_code ? Koha::File::Access::Accounts->find($original_code) : undef;
        my $existing_account_with_new_code = Koha::File::Access::Accounts->find($code);

        if ($account) {
            if ( $original_code eq $code ) {
                $account->update($fields);
                $show_accounts_list = 1;
            } else {
                if ($existing_account_with_new_code) {
                    $fields->{password} = $password;
                    $template->param(
                        create_edit_account => 1,
                        code_in_use         => $existing_account_with_new_code,
                        account             => Koha::File::Access::Account->new($fields),
                    );
                } else {
                    $account->update($fields);
                    $show_accounts_list = 1;
                }
            }
        } else {
            if ($existing_account_with_new_code) {
                $fields->{password} = $password;
                $template->param(
                    create_edit_account => 1,
                    code_in_use         => $existing_account_with_new_code,
                    account             => Koha::File::Access::Account->new($fields),
                );
            } else {
                Koha::File::Access::Account->new($fields)->store();
                $show_accounts_list = 1;
            }
        }
    } elsif ( $op eq 'cud-delete_confirmed' ) {
        my $id      = scalar $input->param('id');
        my $account = Koha::File::Access::Accounts->find($id);
        $account->delete() if $account;
        $show_accounts_list = 1;
    } else {
        $show_accounts_list = 1;
    }

    if ($show_accounts_list) {
        my @accounts = Koha::File::Access::Accounts->search()->as_list();
        $_->password( $crypt->decrypt_hex( $_->password ) ) foreach @accounts;
        $template->param( show_accounts_list => $show_accounts_list, accounts => \@accounts );
    }
}

output_html_with_http_headers( $input, $cookie, $template->output );
