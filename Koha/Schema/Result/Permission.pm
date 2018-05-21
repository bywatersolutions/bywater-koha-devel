use utf8;
package Koha::Schema::Result::Permission;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::Permission

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<permissions>

=cut

__PACKAGE__->table("permissions");

=head1 ACCESSORS

=head2 parent

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 1
  size: 64

=head2 code

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 64

=head2 description

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "parent",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 1, size => 64 },
  "code",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 64 },
  "description",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->set_primary_key("code");

=head1 RELATIONS

=head2 parent

Type: belongs_to

Related object: L<Koha::Schema::Result::Permission>

=cut

__PACKAGE__->belongs_to(
  "parent",
  "Koha::Schema::Result::Permission",
  { code => "parent" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "RESTRICT",
    on_update     => "RESTRICT",
  },
);

=head2 permissions

Type: has_many

Related object: L<Koha::Schema::Result::Permission>

=cut

__PACKAGE__->has_many(
  "permissions",
  "Koha::Schema::Result::Permission",
  { "foreign.parent" => "self.code" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_permissions

Type: has_many

Related object: L<Koha::Schema::Result::UserPermission>

=cut

__PACKAGE__->has_many(
  "user_permissions",
  "Koha::Schema::Result::UserPermission",
  { "foreign.code" => "self.code" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2018-05-21 06:16:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hazAo1EYPHLRItwCzwP1ww


# You can replace this text with custom content, and it will be preserved on regeneration
1;
