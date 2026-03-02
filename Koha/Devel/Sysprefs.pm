package Koha::Devel::Sysprefs;

use Modern::Perl;
use File::Slurp qw(read_file write_file);

use C4::Context;

=head1 NAME

Koha::Devel::Sysprefs

=head1 DESCRIPTION

Handle system preferences operations for developers.

=cut

=head1 API

=cut

=head2 new

my $syspref_handler = Koha::Devel::Sysprefs->new();

Constructor

=cut

sub new {
    my ( $class, $args ) = @_;
    $args ||= {};

    unless ( $args->{filepath} ) {
        $args->{filepath} = sprintf "%s/installer/data/mysql/mandatory/sysprefs.sql",
            C4::Context->config('intranetdir');
    }
    my $self = bless $args, $class;
    return $self;
}

=head2 extract_syspref_from_line

my $pref = $syspref_handler->extract_syspref_from_line($line);

Parse a line from sysprefs.sql and return a hashref containing the different syspref's values

=cut

sub extract_syspref_from_line {
    my ( $self, $line ) = @_;

    if (
        $line    =~ /^INSERT INTO /    # first line
        || $line =~ /^;$/              # last line
        || $line =~ /^--/              # Comment line
        )
    {
        return;
    }

    if (
        $line =~ m/
            '(?<variable>[^'\\]*(?:\\.[^'\\]*)*)',\s*
            '(?<value>[^'\\]*(?:\\.[^'\\]*)*)'
        /xms
        )
    {
        my $variable = $+{variable};
        my $value    = $+{value};

        return {
            variable => $variable,
            value    => $value,
        };
    } else {
        warn "Invalid line: $line";
    }
    return {};
}

=head2 get_sysprefs_from_file

my @sysprefs = $syspref_handler->get_sysprefs_from_file();

Return an array of sysprefs from the SQL file used to populate the system preferences DB table.

=cut

sub get_sysprefs_from_file {
    my ($self) = @_;
    my @sysprefs;
    my @lines = read_file( $self->{filepath} ) or die "Can't open $self->{filepath}: $!";
    for my $line (@lines) {
        chomp $line;

        # FIXME Explode if already exists?
        my $syspref = $self->extract_syspref_from_line($line);
        if ( $syspref && exists $syspref->{variable} ) {
            push @sysprefs, $syspref;
        } elsif ( defined $syspref ) {
            die "$line does not match";
        }
    }
    return @sysprefs;
}

1;
