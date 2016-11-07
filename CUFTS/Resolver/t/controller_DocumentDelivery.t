use strict;
use warnings;
use Test::More;


use Catalyst::Test 'CUFTS::Resolver';
use CUFTS::Resolver::Controller::DocumentDelivery;

ok( request('/documentdelivery')->is_success, 'Request should succeed' );
done_testing();
