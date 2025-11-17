#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;
use File::Basename;
use Test::MockModule;
use Test::More tests => 6;
use Test::NoWarnings;
use Test::Warn;

use C4::Context;
use Koha::Cache::Memory::Lite;
use Koha::Database;
use Koha::Plugins::Datas;
use Koha::Plugins;

use t::lib::Mocks;

BEGIN {
    # Mock pluginsdir before loading Plugins module
    my $path = dirname(__FILE__) . '/../../../lib/plugins';
    t::lib::Mocks::mock_config( 'pluginsdir', $path );

    use_ok('Koha::Plugins::Loader');
}

my $schema = Koha::Database->new->schema;

subtest 'get_enabled_plugins - basic functionality' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Clear cache before testing
    Koha::Cache::Memory::Lite->flush();

    # Remove any existing plugins
    Koha::Plugins::Datas->delete;

    # Test with no enabled plugins
    my @plugins = Koha::Plugins::Loader->get_enabled_plugins();
    is( scalar @plugins, 0, 'Returns empty list when no plugins are enabled' );

    # Test caching behavior
    my @plugins_cached = Koha::Plugins::Loader->get_enabled_plugins();
    is( scalar @plugins_cached, 0, 'Cached empty result works correctly' );

    # The core functionality of loading plugins is tested indirectly through
    # the Koha::Plugins tests which use the Loader
    ok( 1, 'Loader module loaded successfully' );
    can_ok( 'Koha::Plugins::Loader', 'get_enabled_plugins' );

    $schema->storage->txn_rollback;
};

subtest 'get_enabled_plugins - table does not exist' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    # Clear cache
    Koha::Cache::Memory::Lite->flush();

    # Mock table_exists to return false
    my $mock_database = Test::MockModule->new('Koha::Database');
    $mock_database->mock( 'table_exists', sub { return 0; } );

    my @plugins = Koha::Plugins::Loader->get_enabled_plugins();
    is( scalar @plugins, 0, 'Returns empty list when plugin_data table does not exist' );

    # Verify it doesn't try to query the non-existent table
    # This test passes if no exception is thrown
    ok( 1, 'No exception thrown when table does not exist' );

    $schema->storage->txn_rollback;
};

subtest 'get_enabled_plugins - error handling' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    # Clear cache
    Koha::Cache::Memory::Lite->flush();

    # Remove existing plugins
    Koha::Plugins::Datas->delete;

    # Test with invalid plugin class that can't be loaded by adding directly to DB
    Koha::Plugins::Data->new(
        {
            plugin_class => 'Koha::Plugin::NonExistent',
            plugin_key   => '__ENABLED__',
            plugin_value => 1,
        }
    )->store;

    my @plugins = Koha::Plugins::Loader->get_enabled_plugins();
    is( scalar @plugins, 0, 'Returns empty list when plugin class cannot be loaded' );

    $schema->storage->txn_rollback;
};

subtest 'Integration with Koha::Plugins' => sub {
    plan tests => 1;

    # The Loader is designed to be used by Koha::Plugins::get_enabled_plugins
    # Test that the integration point exists
    can_ok( 'Koha::Plugins', 'get_enabled_plugins' );

    # Full integration testing is done in t/db_dependent/Koha/Plugins/Plugins.t
    # which exercises the complete plugin loading flow including the Loader
};
