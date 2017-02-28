package C4::Auth_with_sip;

# Copyright 2017 Kyle M Hall
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

use C4::Context;
use C4::Members qw(AddMember);
use C4::Members::Messaging;

use Koha::SIP::Client;
use Koha::Patrons;
use Koha::Patron::Categories;

use vars qw( @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS );

BEGIN {
    require Exporter;
    @ISA    = qw(Exporter);
    @EXPORT = qw(checkpw_sip);
}

my $sip = C4::Context->config("sip_servers")
  or die 'No "sip_servers" in server hash from KOHA_CONF: ' . $ENV{KOHA_CONF};

my @sip_servers = $sip->{id} ? $sip : map { $sip->{sip_server}->{$_} }
  keys %{ $sip->{sip_server} };

@sip_servers = sort { $a->{precedence} cmp $b->{precedence} } @sip_servers;

=head1 checkpw_sip

    my ( $success, $cardnumber, $userid ) = checkpw_sip( $userid, $password );

    Checks the given user id and password against a set of SIP servers. Returns
    $success if the credentials were verified, along with the cardnumber and userid
    to be used for the patron.

=cut

sub checkpw_sip {
    my ( $userid, $password ) = @_;

    my $server = select_server( $userid, \@sip_servers );

    return 0 unless $server;

    my $sip_patron;
    $sip_patron = fetch_patron( $userid, $password, $server );

    return 0
      unless $sip_patron
      && $sip_patron->{BL} eq 'Y'
      && $sip_patron->{CQ} eq 'Y';

    my $patron = Koha::Patrons->find( { userid => $userid } );

    my $patron_hashref;
    if (   ( $patron && $server->{update} )
        || ( !$patron && $server->{replicate} ) )
    {
        $patron_hashref = sip_to_koha_patron( $sip_patron, $server, $userid );
    }

    if ($patron) {
        $patron->update_password( $userid, $password )
          if $server->{update_password};

        if ( $server->{update} ) {    # A1, B1
            $patron->set($patron_hashref);
            $patron->store();
        }
        else {                        # C1, D1
            return ( 1, $patron->cardnumber, $patron->userid );
        }
    }
    elsif ( $server->{replicate} ) {    # A2, C2
        $patron_hashref->{password} = $password;
        $patron_hashref->{cardnumber} //= $userid;

        my $borrowernumber = C4::Members::AddMember(%$patron_hashref)
          or die "AddMember failed";

        C4::Members::Messaging::SetMessagingPreferencesFromDefaults(
            {
                borrowernumber => $borrowernumber,
                categorycode   => $patron_hashref->{categorycode}
            }
        );
    }
    else {
        return 0;    # B2, D2
    }
}

=head1 sip_to_koha_patron

my $patron_hashref = sip_to_koha_patron( $sip_patron_hashref, $sip_server, $patron_cardnumber );

Returns a Koha-style patron hashref derived from a SIP patron information response hashref and a server mapping definition.

=cut

sub sip_to_koha_patron {
    my $sip_patron = shift;
    my $server     = shift;
    my $cardnumber = shift;

    my $patron_hashref = { cardnumber => $cardnumber, userid => $cardnumber };

    my $mapping = $server->{mapping};

    foreach my $key ( keys %$mapping ) {
        my $data = $sip_patron->{ $mapping->{$key}->{is} };
        unless ( defined $data ) {
            $data = $mapping->{$key}->{content};
        }

        $patron_hashref->{$key} = $data;
    }

    # Fall back to default patron category if the supplied one doesn't exit
    my $patron_category =
      Koha::Patron::Categories->find( $patron_hashref->{categorycode} );
    unless ($patron_category) {
        my $default = $mapping->{categorycode}->{content};
        $patron_hashref->{categorycode} = $default;
    }

    return $patron_hashref;
}

=head1 sip_message_to_hashref

    my $sip_patron_hashref = sip_message_to_hashref( $sip_patron_information_response );

    Converts a raw SIP patron response message to a more useful hashref of fixed and variable fields.

=cut

sub sip_message_to_hashref {
    my ($data) = @_;

    my @parts = split( /\|/, $data );

    my $fixed_fields = shift(@parts);
    my $patron_status_field = substr( $fixed_fields, 2, 14 );
    my $patron_status;
    $patron_status->{charge_privileges_denied} =
      substr( $patron_status_field, 0, 1 );
    $patron_status->{renewal_privileges_denied} =
      substr( $patron_status_field, 1, 1 );
    $patron_status->{recall_privileges_denied} =
      substr( $patron_status_field, 2, 1 );
    $patron_status->{hold_privileges_denied} =
      substr( $patron_status_field, 3, 1 );
    $patron_status->{card_reported_lost} = substr( $patron_status_field, 4, 1 );
    $patron_status->{too_many_items_charged} =
      substr( $patron_status_field, 5, 1 );
    $patron_status->{too_many_items_overdue} =
      substr( $patron_status_field, 6, 1 );
    $patron_status->{too_many_renewals} = substr( $patron_status_field, 7, 1 );
    $patron_status->{too_many_claims_of_items_returned} =
      substr( $patron_status_field, 8, 1 );
    $patron_status->{too_many_items_lost} =
      substr( $patron_status_field, 9, 1 );
    $patron_status->{excessive_outstanding_fines} =
      substr( $patron_status_field, 10, 1 );
    $patron_status->{excessive_outstanding_fees} =
      substr( $patron_status_field, 11, 1 );
    $patron_status->{recall_overdue} = substr( $patron_status_field, 12, 1 );
    $patron_status->{too_many_items_billed} =
      substr( $patron_status_field, 13, 1 );

    my $hold_items_count = substr( $fixed_fields, 37, 4 );

    pop(@parts);

    my %fields = map { substr( $_, 0, 2 ) => substr( $_, 2 ) } @parts;
    $fields{patron_status}    = $patron_status;
    $fields{hold_items_count} = $hold_items_count;

    return \%fields;
}

=head1 select_server

    my $server = select_server( $userid, \@sip_servers );

    Selects the correct SIP server to be checked for a given userid
    and a set of ordered SIP servers.

=cut

sub select_server {
    my ( $userid, $sip_servers ) = @_;

    foreach my $server (@$sip_servers) {
        my $prefix = $server->{prefix};

        # First server without prefix we come across is an automatic match
        return $server unless $prefix;

        # If cardnumber starts with the server prefix, we have a match
        my $match = substr( $userid, 0, length($prefix) ) eq $prefix;
        return $server if $match;
    }
}

=head1 fetch_patron

    my $response = fetch_patron( $userid, $password, $server );

    Returns a raw patron information response for a given user id, password, and server.

=cut

sub fetch_patron {
    my ( $userid, $password, $server ) = @_;

    my $prefix = $server->{prefix};

    # If a cardnumber prefix is set for this server, strip it off the userid
    if ($prefix) {
        my $prefix_length = length($prefix);
        $userid = substr( $userid, $prefix_length );
    }

    my $host       = $server->{host};
    my $port       = $server->{port};
    my $sip_user   = $server->{userid};
    my $sip_pass   = $server->{password};
    my $location   = $server->{location};
    my $terminator = $server->{terminator};

    # Initial Login
    my $client = Koha::SIP::Client->new(
        {
            host       => $host,          # sip server ip
            port       => $port,          # sip server port
            sip_user   => $sip_user,      # sip user
            sip_pass   => $sip_pass,      # sip password
            location   => $location,      # sip location code
            terminator => $terminator,    # CR or CRLF
        }
    );

    my $response = $client->send( { message => 'login' } );

    # Incorrect userid/password for SIP server login attempt
    unless ( substr( $response, 0, 3 ) eq '941' ) {
        return -1;
    }

    # Patron Information request
    $response = $client->send(
        {
            message  => 'patron_information',
            patron   => $userid,
            password => $password,
        }
    );

    $response = sip_message_to_hashref($response);

    return $response;
}

1;
__END__

=head1 NAME

C4::Auth_with_sip - Authenticates Koha users against external SIP servers

=head1 SYNOPSIS

  use C4::Auth_with_sip;

=head1 Configuration

  This module is specific to SIP authentication. It requires one or more working external SIP servers.

  To use it:
    * Add a sip_servers block in KOHA_CONF
    * Establish field mapping in <mapping> element to map SIP2 field codes to Koha field names

  Make sure that ALL required fields are populated by your LDAP database (and mapped in KOHA_CONF).  

=head1 KOHA_CONF and field mapping

Example XML stanza for LDAP configuration in KOHA_CONF.

<config>
 <use_sip>1</use_sip> <!-- enables / disables the entire auth by SIP feature -->

 <sip_servers>
  <sip_server id="sip_server1">
   <precedence>1</precedence>    <!-- precedence is used to set the order in which sip servers will be checked for use -->

   <host>sip.example.com</host>
   <port>6001</port>
   <userid>koha_sip</userid>
   <password>PASSWORD</password>
   <location>LOC</location>

   <prefix>MPL</prefix>

   <replicate>1</replicate>                <!-- add new users from SIP to Koha database -->
   <update>1</update>                      <!-- update existing users in Koha database -->
   <update_password>1</update_password>    <!-- set to 0 if you don't want SIP passwords synced to the local database -->

   <mapping>                               <!-- match koha SQL field names to your SIP field names -->
    <surname      is="AE"                 ></surname>    <!-- Set surname to AE, no default -->
    <branchcode   is=""                   >MPL</branchcode>  <!-- Set branch code to MPL, always -->
    <categorycode is="PC"                 >PT</categorycode> <!-- Set patron category to PC, default to PT if not set or invalid -->
    <email        is="BE"                 ></email>    <!-- Set email to BE, no default -->
   </mapping>
  </sip_server>
 </sip_servers>
</config>

The <mapping> subelements establish the relationship between database table columns and SIP fields.
The element name is the database table column, with the "is" being set to the SIP field name.
Optionally, any content between the element tags is taken as a default value.

=head1 CONFIGURATION

Once a user has been accepted by the LDAP server, there are several possibilities for how Koha will behave, depending on 
your configuration and the presence of a matching Koha user in your local DB:

                          LOCAL
                          USER
 OPTION UPDATE REPLICATE  EXISTS?  RESULT
   A1      1       1        1      OK : We're updating them anyway.
   A2      1       1        0      OK : We're adding them anyway.
   B1      1       0        1      OK : We update them.
   B2      1       0        0     FAIL: We cannot add new user.
   C1      0       1        1      OK : We do nothing.  (Except possibly update password)
   C2      0       1        0      OK : We add the new user.
   D1      0       0        1      OK : We do nothing.  (Except possibly update password)
   D2      0       0        0     FAIL: We cannot add new user.

Note: failure here just means that Koha will fallback to checking the local DB.  That is, a given user could login with
their SIP password OR their local one.  If this is a problem, then you should enable update and supply a mapping for 
password.  Then the local value will be updated at successful LDAP login and the passwords will be synced.

If you choose NOT to update local users, the borrowers table will not be affected at all.
Note that this means that patron passwords may appear to change if LDAP is ever disabled, because
the local table never contained the SIP values.

=head2 replicate

If this tag is set to true, then the patron record in Koha will be created based on the recieved
values from the SIP server if the patron does not exists in the database already.

=head2 update

If this tag is set to true, then the patron record in Koha will be updated based on the
values recieved from the SIP server if a matching patron already exists.

=head2 update_password

If this tag is set to a true value, then the user's SIP password
will be stored (hashed) in the local Koha database. If you don't want this
to happen, then set the value of this to '0'. Note that if passwords are not
stored locally, and the connection to the SIP server fails, then the users
will not be able to log in at all.

This option works independently of 'update' and 'replicate'.

=cut
