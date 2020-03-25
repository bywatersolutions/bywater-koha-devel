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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

# Dummy app for testing the plugin
use Mojolicious::Lite;
use Try::Tiny;

app->log->level('error');

plugin 'Koha::REST::Plugin::Query';

get '/empty' => sub {
    my $c = shift;
    $c->render( json => undef, status => 200 );
};

get '/query' => sub {
    my $c     = shift;
    my $input = {
        _page     => 2,
        _per_page => 3,
        firstname => 'Manuel',
        surname   => 'Cohen Arazi'
    };
    my ( $filtered_params, $reserved_params ) = $c->extract_reserved_params($input);
    $c->render(
        json => {
            filtered_params => $filtered_params,
            reserved_params => $reserved_params
        },
        status => 200
    );
};

get '/query_full' => sub {
    my $c     = shift;
    my $input = {
        _match    => 'exact',
        _order_by => 'blah',
        _page     => 2,
        _per_page => 3,
        firstname => 'Manuel',
        surname   => 'Cohen Arazi'
    };
    my ( $filtered_params, $reserved_params ) = $c->extract_reserved_params($input);
    $c->render(
        json => {
            filtered_params => $filtered_params,
            reserved_params => $reserved_params
        },
        status => 200
    );
};

get '/dbic_merge_sorting' => sub {
    my $c = shift;
    my $attributes = { a => 'a', b => 'b' };
    $attributes = $c->dbic_merge_sorting(
        {
            attributes => $attributes,
            params     => { _match => 'exact', _order_by => [ 'uno', '-dos', '+tres', ' cuatro' ] }
        }
    );
    $c->render( json => $attributes, status => 200 );
};

get '/dbic_merge_sorting_single' => sub {
    my $c = shift;
    my $attributes = { a => 'a', b => 'b' };
    $attributes = $c->dbic_merge_sorting(
        {
            attributes => $attributes,
            params     => { _match => 'exact', _order_by => '-uno' }
        }
    );
    $c->render( json => $attributes, status => 200 );
};

get '/dbic_merge_sorting_to_model' => sub {
    my $c = shift;
    my $attributes = { a => 'a', b => 'b' };
    $attributes = $c->dbic_merge_sorting(
        {
            attributes => $attributes,
            params     => { _match => 'exact', _order_by => [ 'uno', '-dos', '+tres', ' cuatro' ] },
            to_model   => \&to_model
        }
    );
    $c->render( json => $attributes, status => 200 );
};

get '/build_query' => sub {
    my $c = shift;
    my ( $filtered_params, $reserved_params ) =
      $c->extract_reserved_params( $c->req->params->to_hash );
    my $query;
    try {
        $query = $c->build_query_params( $filtered_params, $reserved_params );
        $c->render( json => { query => $query }, status => 200 );
    }
    catch {
        $c->render(
            json => { exception_msg => $_->message, exception_type => ref($_) },
            status => 400
        );
    };
};

get '/stash_embed' => sub {
    my $c = shift;

    try {
        $c->stash_embed(
            {
                spec => {
                    'x-koha-embed' => [
                        'checkouts',
                        'checkouts.item',
                        'library'
                    ]
                }
            }
        );

        $c->render(
            status => 200,
            json   => $c->stash( 'koha.embed' )
        );
    }
    catch {
        $c->render(
            status => 400,
            json   => { error => "$_" }
        );
    };
};

get '/stash_embed_no_spec' => sub {
    my $c = shift;

    try {
        $c->stash_embed({ spec => {} });

        $c->render(
            status => 200,
            json   => $c->stash( 'koha.embed' )
        );
    }
    catch {
        $c->render(
            status => 400,
            json   => { error => "$_" }
        );
    };
};

sub to_model {
    my ($args) = @_;
    $args->{three} = delete $args->{tres}
        if exists $args->{tres};
    return $args;
}

# The tests

use Test::More tests => 4;
use Test::Mojo;

subtest 'extract_reserved_params() tests' => sub {

    plan tests => 8;

    my $t = Test::Mojo->new;

    $t->get_ok('/query')->status_is(200)
      ->json_is( '/filtered_params' =>
          { firstname => 'Manuel', surname => 'Cohen Arazi' } )
      ->json_is( '/reserved_params' => { _page => 2, _per_page => 3 } );

    $t->get_ok('/query_full')->status_is(200)
      ->json_is(
        '/filtered_params' => {
            firstname => 'Manuel',
            surname   => 'Cohen Arazi'
        } )
      ->json_is(
        '/reserved_params' => {
            _page     => 2,
            _per_page => 3,
            _match    => 'exact',
            _order_by => 'blah'
        } );

};

subtest 'dbic_merge_sorting() tests' => sub {

    plan tests => 15;

    my $t = Test::Mojo->new;

    $t->get_ok('/dbic_merge_sorting')->status_is(200)
      ->json_is( '/a' => 'a', 'Existing values are kept (a)' )
      ->json_is( '/b' => 'b', 'Existing values are kept (b)' )->json_is(
        '/order_by' => [
            'uno',
            { -desc => 'dos' },
            { -asc  => 'tres' },
            { -asc  => 'cuatro' }
        ]
      );

    $t->get_ok('/dbic_merge_sorting_to_model')->status_is(200)
      ->json_is( '/a' => 'a', 'Existing values are kept (a)' )
      ->json_is( '/b' => 'b', 'Existing values are kept (b)' )->json_is(
        '/order_by' => [
            'uno',
            { -desc => 'dos' },
            { -asc  => 'three' },
            { -asc  => 'cuatro' }
        ]
      );

    $t->get_ok('/dbic_merge_sorting_single')->status_is(200)
      ->json_is( '/a' => 'a', 'Existing values are kept (a)' )
      ->json_is( '/b' => 'b', 'Existing values are kept (b)' )->json_is(
        '/order_by' => { '-desc' => 'uno' }
      );
};

subtest '_build_query_params_from_api' => sub {

    plan tests => 16;

    my $t = Test::Mojo->new;

    # _match => contains
    $t->get_ok('/build_query?_match=contains&title=Ender&author=Orson')
      ->status_is(200)
      ->json_is( '/query' =>
          { author => { like => '%Orson%' }, title => { like => '%Ender%' } } );

    # _match => starts_with
    $t->get_ok('/build_query?_match=starts_with&title=Ender&author=Orson')
      ->status_is(200)
      ->json_is( '/query' =>
          { author => { like => 'Orson%' }, title => { like => 'Ender%' } } );

    # _match => ends_with
    $t->get_ok('/build_query?_match=ends_with&title=Ender&author=Orson')
      ->status_is(200)
      ->json_is( '/query' =>
          { author => { like => '%Orson' }, title => { like => '%Ender' } } );

    # _match => exact
    $t->get_ok('/build_query?_match=exact&title=Ender&author=Orson')
      ->status_is(200)
      ->json_is( '/query' => { author => 'Orson', title => 'Ender' } );

    # _match => blah
    $t->get_ok('/build_query?_match=blah&title=Ender&author=Orson')
      ->status_is(400)
      ->json_is( '/exception_msg'  => 'Invalid value for _match param (blah)' )
      ->json_is( '/exception_type' => 'Koha::Exceptions::WrongParameter' );

};

subtest 'stash_embed() tests' => sub {

    plan tests => 12;

    my $t = Test::Mojo->new;

    $t->get_ok( '/stash_embed' => { 'x-koha-embed' => 'checkouts,checkouts.item' } )
      ->status_is(200)
      ->json_is( { checkouts => { children => { item => {} } } } );

    $t->get_ok( '/stash_embed' => { 'x-koha-embed' => 'checkouts,checkouts.item,library' } )
      ->status_is(200)
      ->json_is( { checkouts => { children => { item => {} } }, library => {} } );

    $t->get_ok( '/stash_embed' => { 'x-koha-embed' => 'checkouts,checkouts.item,patron' } )
      ->status_is(400)
      ->json_is(
        {
            error => 'Embeding patron is not authorised. Check your x-koha-embed headers or remove it.'
        }
      );

    $t->get_ok( '/stash_embed_no_spec' => { 'x-koha-embed' => 'checkouts,checkouts.item,patron' } )
      ->status_is(400)
      ->json_is(
        {
            error => 'Embedding objects is not allowed on this endpoint.'
        }
      );

};
