use Modern::Perl;

return {
    bug_number => "16117",
    description => "Log invalid borrower cardnumbers and item barcodes",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
            ('LogInvalidItems','0','','Log scanned invalid item identifiers as statistics','YesNo'),
            ('LogInvalidPatrons','0','','Log scanned invalid patron identifiers as statistics','YesNo');
        });
        # sysprefs
        say $out "Added new system preference 'LogInvalidItems'";
        say $out "Added new system preference 'LogInvalidPatrons'";
    },
};
