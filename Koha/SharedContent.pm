package Koha::SharedContent;

# Copyright 2016 BibLibre Morgane Alonso
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use JSON;
use HTTP::Request;
use LWP::UserAgent;

use Koha::Serials;
use Koha::Reports;
use C4::Context;

our $MANA_IP = C4::Context->config('mana_config');

sub manaRequest {
    my $mana_request = shift;
    my $result;
    $mana_request->content_type('application/json');
    my $userAgent = LWP::UserAgent->new;
    if ( $mana_request->method eq "POST" ){
        my $content;
        if ($mana_request->content) {$content = from_json( $mana_request->content )};
        $content->{securitytoken} = C4::Context->preference("ManaToken");
        $mana_request->content( to_json($content) );
    }

    my $response  = $userAgent->request($mana_request);

    eval { $result = from_json( $response->decoded_content ); };
    $result->{code} = $response->code;
    if ( $@ ){
        $result->{msg} = $response->{_msg};
    }
    if ($response->is_error){
        $result->{msg} = "An error occurred, mana server returned: ".$result->{msg};
    }
    return $result ;
}

sub manaIncrementRequest {
    my $resource = shift;
    my $id       = shift;
    my $field    = shift;
    my $step     = shift;
    my $param;
    $param->{step} = $step || 1;
    $param->{id} = $id;
    $param->{resource} = $resource;
    $param = join '&',
       map { defined $param->{$_} ? $_ . "=" . $param->{$_} : () }
           keys %$param;
    my $url = "$MANA_IP/$resource/$id.json/increment/$field?$param";
    my $request = HTTP::Request->new( POST => $url );

    return manaRequest($request);
}

sub manaPostRequest {
    my $resource = shift;
    my $content  = shift;

    my $url = "$MANA_IP/$resource.json";
    my $request = HTTP::Request->new( POST => $url );

    $content->{bulk_import} = 0;
    my $json = to_json( $content, { utf8 => 1 } );
    $request->content($json);
    return manaRequest($request);
}

sub manaShareInfos{
    my ($query, $loggedinuser, $ressourceid, $ressourcetype) = @_;
    my $mana_language;
    if ( $query->param('mana_language') ) {
        $mana_language = $query->param('mana_language');
    }
    else {
        my $result = $mana_language = C4::Context->preference('language');
    }

    my $mana_email;
    if ( $loggedinuser ne 0 ) {
        my $borrower = Koha::Patrons->find($loggedinuser);
        if ($borrower){
            $mana_email = $borrower->email
              if ( ( not defined($mana_email) ) or ( $mana_email eq '' ) );
            $mana_email = $borrower->emailpro
              if ( ( not defined($mana_email) ) or ( $mana_email eq '' ) );
            $mana_email =
              Koha::Libraries->find( C4::Context->userenv->{'branch'} )->branchemail
              if ( ( not defined($mana_email) ) or ( $mana_email eq '' ) );
        }
    }
    $mana_email = C4::Context->preference('KohaAdminEmailAddress')
      if ( ( not defined($mana_email) ) or ( $mana_email eq '' ) );
    my %versions = C4::Context::get_versions();

    my $mana_info = {
        language    => $mana_language,
        kohaversion => $versions{'kohaVersion'},
        exportemail => $mana_email
    };
    my ($ressource, $ressource_mana_info);
    my $packages = "Koha::".ucfirst($ressourcetype)."s";
    my $package = "Koha::".ucfirst($ressourcetype);
    $ressource_mana_info = $package->get_sharable_info($ressourceid);
    $ressource_mana_info = { %$ressource_mana_info, %$mana_info };
    $ressource = $packages->find($ressourceid);

    my $result = Koha::SharedContent::manaPostRequest( $ressourcetype,
        $ressource_mana_info );

    if ( $result and ($result->{code} eq "200" or $result->{code} eq "201") ) {
       eval { $ressource->set( { mana_id => $result->{id} } )->store };
    }
    return $result;
}

sub manaGetRequestWithId {
    my $resource = shift;
    my $id       = shift;

    my $url = "$MANA_IP/$resource/$id.json";
    my $request = HTTP::Request->new( GET => $url );

    return manaRequest($request);
}

sub manaGetRequest {
    my $resource   = shift;
    my $parameters = shift;

    $parameters = join '&',
      map { defined $parameters->{$_} ? $_ . "=" . $parameters->{$_} : () }
      keys %$parameters;
    my $url = "$MANA_IP/$resource.json?$parameters";
    my $request = HTTP::Request->new( GET => $url );

    return manaRequest($request);
}

1;
