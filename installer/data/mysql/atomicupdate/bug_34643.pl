use Modern::Perl;

return {
    bug_number  => "34643",
    description => "Split CircConfirmItemParts for self-checkout and self-checkin",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        my $val = C4::Context->preference('CircConfirmItemParts');
        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences VALUES
            ("CircConfirmItemPartsSCO", ?, NULL, "Deny checkout of multipart items for self-checkout", "Yes/No" ),
            ("CircConfirmItemPartsSCI", ?, NULL, "Deny checkout of multipart items for self-checkin", "Yes/No");
        }, undef, $val, $val
        );

        say $out "Added new system preference 'CircConfirmItemPartsSCO'";
        say $out "Added new system preference 'CircConfirmItemPartsSCI'";
    },
};
