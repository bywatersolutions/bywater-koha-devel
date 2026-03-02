use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);
use File::Slurp             qw(read_file);

return {
    bug_number  => "41834",
    description => "NULL systempreferences's options, explanation and type",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # First fix some discrepancies

        # from updatedatabase.pl 20.12.00.009
        # UseICUStyleQUotes vs UseICUStyleQuotes
        $dbh->do(
            q{
                UPDATE systempreferences
                SET variable="UseICUStyleQuotes"
                WHERE BINARY variable="UseICUStyleQUotes"
            }
        );

        # from db_revs/211200012.pl
        # Syspref was not deleted if no value set
        $dbh->do(
            q{
            DELETE FROM systempreferences WHERE variable='OpacMoreSearches'
        }
        );

        # from db_revs/211200020.pl
        # Syspref was not deleted if no value set
        $dbh->do(
            q{
            DELETE FROM systempreferences WHERE variable='OPACMySummaryNote'
        }
        );

        # Then remove NULL the 3 columns for sysprefs listed in sysprefs.sql
        my $sysprefs_filepath = sprintf "%s/installer/data/mysql/mandatory/sysprefs.sql",
            C4::Context->config('intranetdir');
        my @lines = read_file($sysprefs_filepath) or die "Can't open $sysprefs_filepath: $!";
        my @sysprefs;
        for my $line (@lines) {
            chomp $line;
            next if $line =~ /^INSERT INTO /;    # first line
            next if $line =~ /^;$/;              # last line
            next if $line =~ /^--/;              # Comment line
            if (
                $line =~ m/
                '(?<variable>[^'\\]*(?:\\.[^'\\]*)*)',\s*
            /xms
                )
            {
                push @sysprefs, $+{variable};
            } else {
                die "$line does not match";
            }
        }

        my $updated = $dbh->do(
            q{
            UPDATE systempreferences
            SET options=NULL, explanation=NULL, type=NULL
            WHERE variable IN (} . join( q{,}, map { q{?} } @sysprefs ) . q{)}, undef, @sysprefs
        );

        say $out sprintf "Updated %s system preferences", $updated;
    },
};
