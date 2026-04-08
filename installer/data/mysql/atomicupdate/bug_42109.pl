use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

use YAML::XS;

return {
    bug_number  => "42109",
    description => "Migrate OAI-PMH:ConfFile to OAI-PMH:ExtendedMode",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Read the current ConfFile path
        my ($conf_file) =
            $dbh->selectrow_array(q{SELECT value FROM systempreferences WHERE variable = 'OAI-PMH:ConfFile'});

        # Read file contents if the preference has a value
        my $yaml_content = '';
        if ( $conf_file && -f $conf_file ) {
            eval {
                my $conf = YAML::XS::LoadFile($conf_file);
                $yaml_content = YAML::XS::Dump($conf);
                say_info( $out, "Migrated contents of '$conf_file' to OAI-PMH:ExtendedMode" );
            };
            if ($@) {
                say_warning( $out, "Could not read OAI-PMH:ConfFile '$conf_file': $@" );
            }
        } elsif ($conf_file) {
            say_warning( $out, "OAI-PMH:ConfFile was set to '$conf_file' but the file does not exist" );
        }

        $dbh->do(
            q{INSERT IGNORE INTO systempreferences (variable, value, explanation, options, type)
              VALUES ('OAI-PMH:ExtendedMode', ?, 'YAML configuration for OAI-PMH extended mode. If empty, Koha OAI Server operates in normal mode.', '', 'Textarea')},
            undef, $yaml_content
        );

        $dbh->do(q{DELETE FROM systempreferences WHERE variable = 'OAI-PMH:ConfFile'});

        say $out "Added new system preference 'OAI-PMH:ExtendedMode'";
        say $out "Removed system preference 'OAI-PMH:ConfFile'";
    },
};
