use Modern::Perl;

return {
    bug_number => "33478",
    description => "Customise the format of notices when they are printed",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};

        if( !column_exists( 'letter', 'font_size' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `font_size` int(4) NOT NULL DEFAULT 14 AFTER `updated_on`
          });

          say $out "Added column 'letter.font_size'";
        }

        if( !column_exists( 'letter', 'text_justify' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `text_justify` enum('L','C','R') NOT NULL DEFAULT 'L' AFTER `font_size`
          });

          say $out "Added column 'letter.text_justify'";
        }

        if( !column_exists( 'letter', 'units' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `units` enum('POINT','INCH','MM','CM') NOT NULL DEFAULT 'INCH' AFTER `text_justify`
          });

          say $out "Added column 'letter.units'";
        }

        if( !column_exists( 'letter', 'notice_width' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `notice_width` float NOT NULL DEFAULT 8.5 AFTER `units`
          });

          say $out "Added column 'letter.notice_width'";
        }

        if( !column_exists( 'letter', 'top_margin' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `top_margin` float NOT NULL DEFAULT 0 AFTER `notice_width`
          });

          say $out "Added column 'letter.top_margin'";
        }

        if( !column_exists( 'letter', 'left_margin' ) ) {
          $dbh->do(q{
              ALTER TABLE letter ADD COLUMN `left_margin` float NOT NULL DEFAULT 0 AFTER `top_margin`
          });

          say $out "Added column 'letter.left_margin'";
        }
    },
};
