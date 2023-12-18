use utf8;
package Koha::Schema::Result::LibraryFloatLimit;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::LibraryFloatLimit

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<library_float_limits>

=cut

__PACKAGE__->table("library_float_limits");

=head1 ACCESSORS

=head2 branchcode

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 10

=head2 itemtype

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 10

=head2 float_limit

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "branchcode",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 10 },
  "itemtype",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 10 },
  "float_limit",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</branchcode>

=item * L</itemtype>

=back

=cut

__PACKAGE__->set_primary_key("branchcode", "itemtype");

=head1 RELATIONS

=head2 branchcode

Type: belongs_to

Related object: L<Koha::Schema::Result::Branch>

=cut

__PACKAGE__->belongs_to(
  "branchcode",
  "Koha::Schema::Result::Branch",
  { branchcode => "branchcode" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 itemtype

Type: belongs_to

Related object: L<Koha::Schema::Result::Itemtype>

=cut

__PACKAGE__->belongs_to(
  "itemtype",
  "Koha::Schema::Result::Itemtype",
  { itemtype => "itemtype" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2023-12-19 18:47:35
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:AnpZIyNq9oO1vmDSXmQEMQ

=head2 koha_object_class

=cut

sub koha_object_class {
    'Koha::Library::FloatLimit';
}

=head2 koha_objects_class

=cut

sub koha_objects_class {
    'Koha::Library::FloatLimits';
}

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
