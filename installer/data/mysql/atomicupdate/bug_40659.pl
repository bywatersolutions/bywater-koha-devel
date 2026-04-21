use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "40659",
    description => "Add VIRTUALCARD default letter",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO letter
            (module, code, branchcode, name, is_html, title, content, message_transport_type, lang)
            VALUES ('members','VIRTUALCARD','','OPAC virtual card',1,'OPAC virtual card','','email','default');
        }
        ) == 1 && say_success( $out, "Added VIRTUALCARD default letter" );
    },
};
