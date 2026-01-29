use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "23260",
    description =>
        "Make created_on from items_last_borrower not update to current timestamp ON UPDATE, and add AnonymizeLastBorrower and AnonymizeLastBorrowerDays preferences",
    up => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            ALTER TABLE items_last_borrower
            MODIFY COLUMN borrowernumber int(11) NULL,
            MODIFY created_on timestamp NOT NULL DEFAULT current_timestamp()
        }
        );
        say_success( $out, "Fixed items_last_borrower.created_on column to prevent automatic timestamp updates" );

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
            ('AnonymizeLastBorrower','0',NULL,'If enabled, anonymize item\'s last borrower','YesNo'),
            ('AnonymizeLastBorrowerDays','0',NULL,'Item\'s last borrower older than this preference will be anonymized','Integer')
        }
        );
        say_success( $out, "Added new system preferences 'AnonymizeLastBorrower' and 'AnonymizeLastBorrowerDays'" );
    },
};
