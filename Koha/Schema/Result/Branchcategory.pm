use utf8;
package Koha::Schema::Result::Branchcategory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::Branchcategory

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<branchcategories>

=cut

__PACKAGE__->table("branchcategories");

=head1 ACCESSORS

=head2 categorycode

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 10

=head2 categoryname

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 codedescription

  data_type: 'mediumtext'
  is_nullable: 1

=head2 categorytype

  data_type: 'varchar'
  is_nullable: 1
  size: 16

=head2 show_in_pulldown

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "categorycode",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 10 },
  "categoryname",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "codedescription",
  { data_type => "mediumtext", is_nullable => 1 },
  "categorytype",
  { data_type => "varchar", is_nullable => 1, size => 16 },
  "show_in_pulldown",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</categorycode>

=back

=cut

__PACKAGE__->set_primary_key("categorycode");

=head1 RELATIONS

=head2 branchrelations

Type: has_many

Related object: L<Koha::Schema::Result::Branchrelation>

=cut

__PACKAGE__->has_many(
  "branchrelations",
  "Koha::Schema::Result::Branchrelation",
  { "foreign.categorycode" => "self.categorycode" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 circulation_rules

Type: has_many

Related object: L<Koha::Schema::Result::CirculationRule>

=cut

__PACKAGE__->has_many(
  "circulation_rules",
  "Koha::Schema::Result::CirculationRule",
  { "foreign.categorycode" => "self.categorycode" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 branchcodes

Type: many_to_many

Composing rels: L</branchrelations> -> branchcode

=cut

__PACKAGE__->many_to_many("branchcodes", "branchrelations", "branchcode");


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2017-03-06 17:39:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:U+iAnklf50zzXkAFKmuBAw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
