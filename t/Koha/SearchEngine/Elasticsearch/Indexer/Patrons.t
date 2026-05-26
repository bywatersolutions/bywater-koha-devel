#!/usr/bin/env perl

# Tests for Koha::SearchEngine::Elasticsearch::Indexer::Patrons::_build_document

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 5;
use Test::MockModule;
use Test::MockObject;

use t::lib::Mocks;

# Mock dependencies so we can load the module without DB/ES
my $es_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
$es_mock->mock( 'new', sub { bless { index => 'patrons', index_name => 'koha_patrons' }, $_[0] } );

my $indexer_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Indexer');
$indexer_mock->mock( 'new', sub { bless { index => 'patrons', index_name => 'koha_patrons' }, $_[0] } );

use_ok('Koha::SearchEngine::Elasticsearch::Indexer::Patrons');

sub _mock_patron {
    my (%args) = @_;

    my $patron   = Test::MockObject->new();
    my %defaults = (
        borrowernumber      => 42,
        cardnumber          => 'CARD001',
        surname             => 'Smith',
        firstname           => 'John',
        preferred_name      => undef,
        middle_name         => 'Michael',
        othernames          => undef,
        initials            => 'JMS',
        title               => 'Mr',
        userid              => 'jsmith',
        streetnumber        => '123',
        streettype          => 'Ave',
        address             => '123 Main St',
        address2            => 'Apt 4',
        city                => 'Springfield',
        state               => 'IL',
        zipcode             => '62701',
        country             => 'US',
        email               => 'john@example.com',
        emailpro            => undef,
        B_email             => undef,
        phone               => '555-1234',
        phonepro            => undef,
        mobile              => '555-5678',
        B_phone             => undef,
        altcontactphone     => undef,
        B_address           => undef,
        B_address2          => undef,
        B_city              => undef,
        B_state             => undef,
        B_zipcode           => undef,
        B_country           => undef,
        altcontactfirstname => undef,
        altcontactsurname   => undef,
        altcontactaddress1  => undef,
        altcontactaddress2  => undef,
        altcontactaddress3  => undef,
        categorycode        => 'PT',
        branchcode          => 'CPL',
        dateofbirth         => '1990-05-15',
        dateenrolled        => '2020-01-01',
        dateexpiry          => '2025-01-01',
        sort1               => undef,
        sort2               => undef,
        borrowernotes       => undef,
        opacnote            => undef,
        debarred            => undef,
        gonenoaddress       => 0,
        lost                => 0,
        anonymized          => 0,
        %args,
    );

    for my $field ( keys %defaults ) {
        $patron->mock( $field, sub { $defaults{$field} } );
    }

    # Mock related objects for computed fields
    my $checkouts_mock = Test::MockObject->new();
    $checkouts_mock->mock( 'count', sub { 0 } );
    $patron->mock( 'checkouts', sub { $checkouts_mock } );

    my $account_mock = Test::MockObject->new();
    $account_mock->mock( 'balance', sub { 0 } );
    $patron->mock( 'account', sub { $account_mock } );

    my $library_mock = Test::MockObject->new();
    $library_mock->mock( 'branchname', sub { 'Centerville' } );
    $patron->mock( 'library', sub { $library_mock } );

    my $category_mock = Test::MockObject->new();
    $category_mock->mock( 'description', sub { 'Patron' } );
    $patron->mock( 'category', sub { $category_mock } );

    return $patron;
}

sub _mock_attributes {
    my (@attrs) = @_;

    my @list;
    for my $attr (@attrs) {
        my $obj = Test::MockObject->new();
        $obj->mock( 'code',             sub { $attr->{code} } );
        $obj->mock( 'attribute',        sub { $attr->{value} } );
        $obj->mock( 'authorised_value', sub { undef } );
        push @list, $obj;
    }

    my $rs = Test::MockObject->new();
    $rs->mock( 'as_list', sub { @list } );
    return $rs;
}

subtest '_build_document - basic patron' => sub {
    plan tests => 13;

    my $patron = _mock_patron();
    $patron->mock( 'extended_attributes', sub { _mock_attributes() } );

    my $indexer = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Indexer::Patrons';
    my $doc = $indexer->_build_document($patron);

    is( $doc->{patron_id},   42,                 'patron_id (mapped from borrowernumber)' );
    is( $doc->{cardnumber},  'CARD001',          'cardnumber' );
    is( $doc->{surname},     'Smith',            'surname' );
    is( $doc->{firstname},   'John',             'firstname' );
    is( $doc->{city},        'Springfield',      'city' );
    is( $doc->{category_id}, 'PT',               'category_id (mapped from categorycode)' );
    is( $doc->{library_id},  'CPL',              'library_id (mapped from branchcode)' );
    is( $doc->{email},       'john@example.com', 'email' );

    # Booleans
    is_deeply( $doc->{restricted},        \0, 'debarred is false' );
    is_deeply( $doc->{incorrect_address}, \0, 'gonenoaddress is false' );
    is_deeply( $doc->{patron_card_lost},  \0, 'lost is false' );

    # Composite field
    like( $doc->{patron_name}, qr/Smith/, 'patron_name contains surname' );
    like( $doc->{patron_name}, qr/John/,  'patron_name contains firstname' );
};

subtest '_build_document - with extended attributes' => sub {
    plan tests => 5;

    my $patron = _mock_patron();
    $patron->mock(
        'extended_attributes',
        sub {
            _mock_attributes(
                { code => 'INSTID', value => '12345' },
                { code => 'INSTID', value => '67890' },
                { code => 'CAMPUS', value => 'North' },
            );
        }
    );

    my $indexer = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Indexer::Patrons';
    my $doc = $indexer->_build_document($patron);

    # Nested extended_attributes
    is( scalar @{ $doc->{extended_attributes} }, 3,        '3 nested attribute entries' );
    is( $doc->{extended_attributes}[0]{code},    'INSTID', 'first attr code' );
    is( $doc->{extended_attributes}[0]{value},   '12345',  'first attr value' );

    # Dynamic fields
    is_deeply( $doc->{ext_attr_INSTID}, [ '12345', '67890' ], 'ext_attr_INSTID has both values' );
    is_deeply( $doc->{ext_attr_CAMPUS}, ['North'],            'ext_attr_CAMPUS has one value' );
};

subtest '_build_document - debarred patron' => sub {
    plan tests => 1;

    my $patron = _mock_patron( debarred => '2025-12-31' );
    $patron->mock( 'extended_attributes', sub { _mock_attributes() } );

    my $indexer = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Indexer::Patrons';
    my $doc = $indexer->_build_document($patron);

    is_deeply( $doc->{restricted}, \1, 'restricted is true when set' );
};
