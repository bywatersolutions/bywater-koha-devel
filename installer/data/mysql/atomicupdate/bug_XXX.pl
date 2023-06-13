use Modern::Perl;

return {
    bug_number => 'XXX',
    description => 'Add system preference AutoIncrementBarcode',
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (`variable`, `value`, `options`, `explanation`, `type`)
            VALUES ('autoBarcodeValue', '1', NULL, 'Use the value for the next auto-barcoded item, then increment it.', 'Integer')
        });
    },
};
