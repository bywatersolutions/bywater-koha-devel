use Modern::Perl;

return {
    bug_number => "32902",
    description => "Add new item overlay action 'replace_if_bib_match'",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};
        $dbh->do(q{
            ALTER TABLE import_batches MODIFY item_action
            enum('always_add','add_only_for_matches','add_only_for_new','ignore','replace','replace_if_bib_match') NOT NULL DEFAULT 'always_add'
            COMMENT 'what to do with item records'});
        },
};
