use Modern::Perl;

return {
    bug_number  => "41479",
    description =>
        "Remove system preferences BakerTaylorBookstoreURL, BakerTaylorEnabled, BakerTaylorPassword, BakerTaylorUsername",
    up => sub {
        my ($args) = @_;
        my $dbh = $args->{dbh};

        $dbh->do(
            q{ DELETE FROM systempreferences WHERE variable IN ('BakerTaylorBookstoreURL', 'BakerTaylorEnabled', 'BakerTaylorPassword', 'BakerTaylorUsername')}
        );
    },
    }
