#!/usr/bin/env perl

# Copyright (C) 2025 jenkins-helper-scripts contributors
#
# This file is part of jenkins-helper-scripts.
#
# jenkins-helper-scripts is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# jenkins-helper-scripts is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with jenkins-helper-scripts; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

# Auto-install required modules if missing
BEGIN {
    my @required = qw(Modern::Perl IPC::Cmd);
    my @missing;

    for my $module (@required) {
        eval "require $module; 1" or push @missing, $module;
    }

    if (@missing) {
        print "Installing missing Perl modules: " . join( ', ', @missing ) . "\n";
        system( 'cpan', '-i', @missing ) == 0 or die "Failed to install modules: $!\n";
        exec( $^X, $0, @ARGV );    # Re-exec script with new modules
    }
}

use File::Temp qw(tempdir);
use Getopt::Long;
use Cwd      qw(abs_path getcwd);
use IPC::Cmd qw(run run_forked);

# Parse command line options
my $cleanup        = 1;      # Default to cleanup
my $help           = 0;
my $name           = '';
my $verbose        = 0;
my $warmup_timeout = 300;    # Default warmup timeout in seconds
my $force_cleanup  = 0;      # Force cleanup of existing instances
my $selenium       = 0;      # Enable selenium support
my $search_engine  = '';     # Search engine to use (zebra, es6, es7, es8, os1, os2)

# Test control options (from run_tests.pl)
my $run_all_tests           = 0;
my $run_light_tests         = 0;
my $run_all_perl_tests      = 0;
my $run_light_test_suite    = 0;
my $run_elastic_tests_only  = 0;
my $run_selenium_tests_only = 0;
my $run_cypress_tests_only  = 0;
my $run_db_upgrade_only     = 0;
my $run_db_compare_only     = 0;
my $prove_cpus              = '';
my $compare_with            = '';
my $run_only                = '';
my $with_coverage           = 0;

GetOptions(
    'cleanup!'         => \$cleanup,
    'help|h'           => \$help,
    'name=s'           => \$name,
    'verbose|v'        => \$verbose,
    'warmup-timeout=i' => \$warmup_timeout,
    'force-cleanup'    => \$force_cleanup,
    'selenium'         => \$selenium,
    'search-engine=s'  => \$search_engine,

    # Test control options (from run_tests.pl)
    'prove-cpus=s'            => \$prove_cpus,
    'with-coverage'           => \$with_coverage,
    'run-all-tests'           => \$run_all_tests,
    'run-light-tests'         => \$run_light_tests,
    'run-all-perl-tests'      => \$run_all_perl_tests,
    'run-light-test-suite'    => \$run_light_test_suite,
    'run-elastic-tests-only'  => \$run_elastic_tests_only,
    'run-cypress-tests-only'  => \$run_cypress_tests_only,
    'run-selenium-tests-only' => \$run_selenium_tests_only,
    'run-db-upgrade-only'     => \$run_db_upgrade_only,
    'run-db-compare-only'     => \$run_db_compare_only,
    'compare-with=s'          => \$compare_with,
    'run-only=s'              => \$run_only,
) or die "Error in command line arguments\n";

$with_coverage ||= ( $ENV{COVERAGE} && $ENV{COVERAGE} eq 'yes' );

if ($help) {
    print_help();
    exit 0;
}

# Save current working directory (the Koha repo being tested)
my $koha_repo = getcwd();

# Determine KTD instance name
my $instance_name;
if ($name) {
    $instance_name = $name;
    print "Using provided name: $instance_name for KTD instance\n";
} else {

    # Get short commit hash for naming the KTD instance
    $instance_name = qx{git rev-parse --short HEAD};
    chomp $instance_name;
    die "Failed to get commit hash. Are you in a git repository?\n" unless $instance_name;
    print "Using commit hash: $instance_name for KTD instance name\n";
}

# Create temporary directory for KTD
my $tmp_dir = tempdir( 'ktd-test-XXXXXX', TMPDIR => 1, CLEANUP => $cleanup );
print "Created temporary directory: $tmp_dir\n";

# Save original directory to restore later
my $original_dir = getcwd();

# Clone KTD into temp directory
print "Cloning koha-testing-docker...\n";
my $ktd_branch = $ENV{KTD_BRANCH} || 'main';
chdir($tmp_dir) or die "Cannot chdir to $tmp_dir: $!";
run_cmd(
    qq{git clone --branch $ktd_branch --single-branch --depth 1 https://gitlab.com/koha-community/koha-testing-docker.git},
    { exit_on_error => 1, real_time => $verbose }
);

my $ktd_home = "$tmp_dir/koha-testing-docker";
chdir($ktd_home) or die "Cannot chdir to $ktd_home: $!";

# Set up environment variables
$ENV{KTD_HOME}      = $ktd_home;
$ENV{SYNC_REPO}     = $ENV{SYNC_REPO} || $koha_repo;
$ENV{LOCAL_USER_ID} = qx{id -u};
chomp $ENV{LOCAL_USER_ID};
$ENV{KOHA_IMAGE}         = $ENV{KOHA_IMAGE} || 'main';
$ENV{RUN_TESTS_AND_EXIT} = 'no';                         # We run tests manually via ktd --shell
$ENV{JUNIT_OUTPUT_FILE}  = 'junit_main.xml';

# Copy defaults.env to .env
run_cmd( q{cp env/defaults.env .env}, { exit_on_error => 1, real_time => $verbose } );

# TODO: Rethink if we need to patch .env file with current environment variables
# or if ktd's environment variable override logic is sufficient.
{
    local @ARGV = ('.env');
    local $^I   = '';         # in-place editing
    while (<>) {
        if (/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) {
            my ( $key, $val ) = ( $1, $2 );
            if ( exists $ENV{$key} ) {
                $_ = "$key=$ENV{$key}\n";
            }
        }
        print;
    }
}

# Build environment for ktd commands
my $ktd_env = {%ENV};
for my $key (qw(SYNC_REPO LOCAL_USER_ID KOHA_IMAGE RUN_TESTS_AND_EXIT JUNIT_OUTPUT_FILE)) {
    delete $ktd_env->{$key} unless defined $ENV{$key} && $ENV{$key} ne '';
}

# Don't pass COVERAGE environment variable - use --with-coverage parameter instead
delete $ktd_env->{COVERAGE};

# Determine ktd flags needed
my @ktd_flags = (
    '--proxy',    # required to avoid port collisions
    '--name', $instance_name
);

# Check for existing instance and clean up if needed
check_and_cleanup_existing_instance( $ktd_home, $instance_name, $force_cleanup );

# Selenium support
if ( $run_all_tests || $run_all_perl_tests || $run_selenium_tests_only || $run_only || $selenium ) {
    push @ktd_flags, '--selenium';
}

# Elasticsearch/OpenSearch support
if ( !$search_engine ) {

    # Auto-detect based on test switches that require Elasticsearch
    if ( $run_all_tests || $run_all_perl_tests || $run_elastic_tests_only ) {
        $search_engine = 'es8';    # Default to es8
    } else {
        $search_engine = 'zebra';    # Default to zebra for other tests
    }
}
push @ktd_flags, "--search-engine", $search_engine;

my $ktd_flags = join( ' ', @ktd_flags );

# Create log file for storing KTD startup logs
my $log_file = "$tmp_dir/ktd_startup.log";
print "Storing KTD logs to: $log_file\n";

# Launch KTD instance
print "Launching KTD instance '$instance_name' with flags: $ktd_flags\n";

# Ensure proxy network exists for --proxy flag
if ( $ktd_flags =~ /--proxy/ ) {
    print "Checking for proxy network...\n";
    my $network_check = `docker network ls | grep -e '\\sproxy\\s'`;
    if ( !$network_check ) {
        print "Creating proxy network...\n";
        run_cmd( "docker network create proxy", { exit_on_error => 1, real_time => $verbose } );
    }
}

# Pull images quietly before launching
print "Pulling docker images...\n";
my $ktd_pull_cmd = "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd $ktd_flags pull -q";
run_cmd( $ktd_pull_cmd, { exit_on_error => 1, real_time => 0, env => $ktd_env } );

my $ktd_up_cmd = "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd $ktd_flags up -d";
run_cmd( $ktd_up_cmd, { exit_on_error => 1, real_time => $verbose, env => $ktd_env } );

# Wait for KTD to be ready while capturing logs
print "Waiting for KTD instance to be ready (timeout: ${warmup_timeout}s)...\n";
wait_ready_with_logs( $ktd_home, $instance_name, $log_file, $warmup_timeout );

# Build test command based on TEST_SUITE
my $test_cmd = build_test_command();

print "Running tests: $test_cmd\n";
my $test_exit_code = 0;
eval {
    run_cmd(
        qq{export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd --name $instance_name --shell --run "source ~/.bashrc && $test_cmd"},
        { exit_on_error => 1, real_time => 1, env => $ktd_env }
    );
};
if ($@) {
    print "Tests failed!\n";
    $test_exit_code = 1;
}

# Cleanup
if ($cleanup) {
    print "Cleaning up KTD instance...\n";
    run_cmd(
        "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd --name $instance_name down",
        { real_time => $verbose, env => $ktd_env }
    );
    print "Restoring original directory...\n";
    chdir($original_dir) or warn "Cannot chdir back to $original_dir: $!";
    print "Temporary directory will be cleaned up automatically.\n";
} else {
    print "Skipping cleanup. KTD instance '$instance_name' is still running.\n";
    print "Restoring original directory...\n";
    chdir($original_dir) or warn "Cannot chdir back to $original_dir: $!";
    print "Temporary directory: $tmp_dir\n";
    print "To cleanup manually, run:\n";
    print "  export KTD_HOME=$ktd_home\n";
    print "  export PATH=\$KTD_HOME/bin:\$PATH\n";
    print "  ktd --name $instance_name down\n";
    print "  rm -rf $tmp_dir\n";
}

exit $test_exit_code;

# Subroutines

sub check_and_cleanup_existing_instance {
    my ( $ktd_home, $instance_name, $force_cleanup ) = @_;

    # Check if instance exists
    my $check_cmd =
        "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && docker compose -p $instance_name ps -q";
    my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) = IPC::Cmd::run(
        command => $check_cmd,
        verbose => 0,
    );

    if ( $success && $stdout_buf && @$stdout_buf ) {

        # Instance exists
        if ($force_cleanup) {
            print "Found existing instance '$instance_name', cleaning up...\n";
            my $cleanup_cmd =
                "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd --name $instance_name down";
            run_cmd( $cleanup_cmd, { real_time => 0 } );
        } else {
            die "Instance '$instance_name' already exists. Use --force-cleanup to remove it first.\n";
        }
    }
}

sub wait_ready_with_logs {
    my ( $ktd_home, $instance_name, $log_file, $timeout ) = @_;

    my $start_time   = time;
    my $logs_running = 1;

    # Use run_forked directly - it handles all process management
    my $log_pid = fork();
    if ( $log_pid == 0 ) {

        # Child: just call run_forked (no nested forking)
        run_forked(
            "docker compose -p $instance_name logs -f",
            {
                timeout        => $timeout,
                stdout_handler => sub {
                    print $_[0] if $logs_running;
                },
                stderr_handler => sub {
                    print STDERR $_[0] if $logs_running;
                },
                discard_output => 1,
            }
        );
        exit;
    }

    # Single wait-ready call handles all timing logic
    my ($ready) = IPC::Cmd::run(
        command =>
            "export KTD_HOME=$ktd_home && export PATH=\$KTD_HOME/bin:\$PATH && ktd --name $instance_name --wait-ready $timeout",
        verbose => 0,
        timeout => $timeout + 5,    # Add buffer for command execution
    );

    # Stop log collection and cleanup
    $logs_running = 0;
    kill 'TERM', $log_pid if $log_pid;
    waitpid( $log_pid, 0 ) if $log_pid;

    if ($ready) {
        my $elapsed = time - $start_time;
        print "\nKTD instance ready after ${elapsed}s!\n";
    } else {
        die "\nTimeout waiting for KTD instance to be ready after ${timeout}s\n";
    }
}

sub build_test_command {

    my @cmd_parts = ( 'perl', '/kohadevbox/misc4dev/run_tests.pl' );

    # Determine which tests to run: CLI options first, then ENV, then default
    if ($run_only) {
        push @cmd_parts, '--run-only', $run_only;
    } elsif ($run_all_tests) {
        push @cmd_parts, '--run-all-tests';
    } elsif ($run_light_tests) {
        push @cmd_parts, '--run-light-tests';
    } elsif ($run_all_perl_tests) {
        push @cmd_parts, '--run-all-perl-tests';
    } elsif ($run_light_test_suite) {
        push @cmd_parts, '--run-light-test-suite';
    } elsif ($run_elastic_tests_only) {
        push @cmd_parts, '--run-elastic-tests-only';
    } elsif ($run_selenium_tests_only) {
        push @cmd_parts, '--run-selenium-tests-only';
    } elsif ($run_cypress_tests_only) {
        push @cmd_parts, '--run-cypress-tests-only';
    } elsif ($run_db_upgrade_only) {
        push @cmd_parts, '--run-db-upgrade-only';
    } elsif ($run_db_compare_only) {
        push @cmd_parts, '--run-db-compare-only';
    } else {

        # Default: run all tests
        push @cmd_parts, '--run-all-tests';
    }

    # Add additional options
    if ($prove_cpus) {
        push @cmd_parts, '--prove-cpus', $prove_cpus;
    }
    if ($compare_with) {
        push @cmd_parts, '--compare-with', $compare_with;
    }

    # Add coverage if requested via CLI (pass-through parameter, not environment)
    if ($with_coverage) {
        push @cmd_parts, '--with-coverage';
    }

    return join( ' ', @cmd_parts );
}

sub run_cmd {
    my ( $cmd, $params ) = @_;
    my $exit_on_error = $params->{exit_on_error} // 0;
    my $real_time     = $params->{real_time}     // 0;
    my $env           = $params->{env}           // {};

    my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) = IPC::Cmd::run(
        command => $cmd,
        verbose => $real_time,
        timeout => 10800,        # 3 hour timeout for full test suite
        %$env ? ( env => $env ) : (),
    );

    if ( !$success && $exit_on_error ) {
        die "Command failed: $error_message\n";
    }

    return $success;
}

sub print_help {
    print <<'HELP';
Usage: koha_tests_runner.pl [OPTIONS]

Runs Koha tests in an isolated KTD (Koha Testing Docker) instance.

This script:
  1. Creates a temporary directory
  2. Clones koha-testing-docker into it
  3. Launches a named KTD instance (using commit hash or custom name)
  4. Uses --proxy to avoid port collisions for parallel runs
  5. Runs tests using /kohadevbox/misc4dev/run_tests.pl
  6. Optionally cleans up the instance and temporary directory

OPTIONS:
  --name <name>
      Name for the KTD instance. If not provided, uses the short commit hash
      from the current git repository.

  --search-engine <engine>
      Search engine to use: zebra, es7, es8, os1, os2 (default: zebra, falls back to es8 when ES required)
      Falls back to es8 for tests requiring Elasticsearch, zebra otherwise.
      Run 'ktd --search-engine list' to see all available options.

  --selenium
      Enable Selenium support for browser-based tests.

  --force-cleanup
      Clean up any existing KTD instance with the same name before starting.
      Without this flag, the script will exit if an instance already exists.

  --warmup-timeout <seconds>
      Timeout in seconds to wait for KTD instance to be ready (default: 300).

  --cleanup / --no-cleanup
      Whether to cleanup the KTD instance and temp directory after running.
      Default: --cleanup

  -v, --verbose
      Show service logs during KTD warmup for debugging.

TEST CONTROL OPTIONS:
  --run-all-tests
      Run all available tests (default behavior).

  --run-light-tests
      Run light test suite (faster subset of tests).

  --run-selenium-tests-only
      Run only Selenium tests.

  --run-cypress-tests-only
      Run only Cypress tests.

  --run-only <test_pattern>
      Run only tests matching the specified pattern.

  --with-coverage
      Enable coverage reporting (overrides COVERAGE environment variable).

  -h, --help
      Show this help message.

ENVIRONMENT VARIABLES:
  KOHA_IMAGE        Koha docker image tag (default: 'main')
  KTD_BRANCH        KTD branch to use (default: 'main')
  SYNC_REPO         Path to Koha repository (default: current directory)

EXAMPLES:
  # Run full test suite with cleanup (uses commit hash as name)
  ./koha_tests_runner.pl

  # Run with a custom instance name
  ./koha_tests_runner.pl --name my-test-run

  # Run with verbose logging to debug startup issues
  ./koha_tests_runner.pl --verbose

  # Run with Selenium support enabled
  ./koha_tests_runner.pl --selenium

  # Run with specific search engine
  ./koha_tests_runner.pl --search-engine es8

  # Run tests on a specific Koha branch with bookworm
  KOHA_IMAGE=bookworm ./koha_tests_runner.pl

HELP
}
