use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_failure say_success say_info);

return {
    bug_number  => '38136',
    description => 'Add localization.property',
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( column_exists( 'localization', 'property' ) ) {
            $dbh->do("alter table `localization` add `property` varchar(100) null after `code`");
            $dbh->do("update `localization` set `property` = 'description', entity = 'Itemtype'");
            $dbh->do("alter table `localization` modify `property` varchar(100) not null");
            $dbh->do("alter table `localization` drop key `entity_code_lang`");
            $dbh->do(
                "alter table `localization` add unique key `entity_code_property_lang` (`entity`, `code`, `property`, `lang`)"
            );

            say_success( $out, 'Added column localization.property and updated localization.entity values' );
        }

    },
};
