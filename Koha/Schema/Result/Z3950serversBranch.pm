use utf8;
package Koha::Schema::Result::Z3950serversBranch;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::Z3950serversBranch

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<z3950servers_branches>

=cut

__PACKAGE__->table("z3950servers_branches");

=head1 ACCESSORS

=head2 server_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

z3950server id

=head2 branchcode

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 10

branch code

=cut

__PACKAGE__->add_columns(
  "server_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "branchcode",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 10 },
);

=head1 PRIMARY KEY

=over 4

=item * L</server_id>

=item * L</branchcode>

=back

=cut

__PACKAGE__->set_primary_key("server_id", "branchcode");

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

=head2 server

Type: belongs_to

Related object: L<Koha::Schema::Result::Z3950server>

=cut

__PACKAGE__->belongs_to(
  "server",
  "Koha::Schema::Result::Z3950server",
  { id => "server_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-02-25 12:31:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MsoJ8jHSn20dUzL2cU7pJA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
