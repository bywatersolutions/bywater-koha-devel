package Koha::Plugin::TestBarcodes2;

use Scalar::Util qw( looks_like_number );

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

our $VERSION = 1.01;
our $metadata = {
    name            => 'TestBarcodes2 Plugin',
    author          => 'Kyle M Hall',
    description     => 'TestBarcodes2 plugin',
    date_authored   => '2013-01-14',
    date_updated    => '2013-01-14',
    minimum_version => '3.11',
    maximum_version => undef,
    version         => $VERSION,
    my_example_tag  => 'find_me',
};

sub new {
    my ( $class, $args ) = @_;
    $args->{'metadata'} = $metadata;
    my $self = $class->SUPER::new($args);
    return $self;
}

sub item_barcode_transform {
    my ( $self, $barcode ) = @_;
    return $barcode unless looks_like_number( $barcode );
    return $barcode + 2;
}

sub patron_barcode_transform {
    my ( $self, $barcode ) = @_;
    return $barcode unless looks_like_number( $barcode );
    return $barcode + 2;
}

1;
