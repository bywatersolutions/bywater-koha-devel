#!/usr/bin/perl
#
# Copyright 2014 Catalyst IT
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

use Test::More tests => 17;
use Data::Dumper;
use Koha::Database;

BEGIN {
    use_ok('Koha::ItemTypes');
}

my $database = Koha::Database->new();
my $schema   = $database->schema();
$schema->txn_begin;

$schema->resultset('Itemtype')->create(
    {
        itemtype       => 'type1',
        description    => 'description',
        rentalcharge   => '0.00',
        imageurl       => 'imageurl',
        summary        => 'summary',
        checkinmsg     => 'checkinmsg',
        checkinmsgtype => 'checkinmsgtype',
    }
);
$schema->resultset('Itemtype')->create(
    {
        itemtype       => 'type2',
        description    => 'description',
        rentalcharge   => '0.00',
        imageurl       => 'imageurl',
        summary        => 'summary',
        checkinmsg     => 'checkinmsg',
        checkinmsgtype => 'checkinmsgtype',
    }
);
my $itypes = Koha::ItemTypes->new();

my @types = $itypes->get_itemtype( 'type1', 'type2' );

my $type = $types[0];
ok( defined($type), 'first result' );
is( $type->code,           'type1',          'itemtype/code' );
is( $type->description,    'description',    'description' );
is( $type->rentalcharge,   '0.0000',             'rentalcharge' );
is( $type->imageurl,       'imageurl',       'imageurl' );
is( $type->summary,        'summary',        'summary' );
is( $type->checkinmsg,     'checkinmsg',     'checkinmsg' );
is( $type->checkinmsgtype, 'checkinmsgtype', 'checkinmsgtype' );

$type = $types[1];
ok( defined($type), 'second result' );
is( $type->code,           'type2',          'itemtype/code' );
is( $type->description,    'description',    'description' );
is( $type->rentalcharge,   '0.0000',             'rentalcharge' );
is( $type->imageurl,       'imageurl',       'imageurl' );
is( $type->summary,        'summary',        'summary' );
is( $type->checkinmsg,     'checkinmsg',     'checkinmsg' );
is( $type->checkinmsgtype, 'checkinmsgtype', 'checkinmsgtype' );

$schema->txn_rollback;
