use utf8;
package Koha::Schema::Result::VendorEdiAccount;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::VendorEdiAccount

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<vendor_edi_accounts>

=cut

__PACKAGE__->table("vendor_edi_accounts");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 0

=head2 host

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 username

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 password

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 last_activity

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 vendor_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 download_directory

  data_type: 'text'
  is_nullable: 1

=head2 upload_directory

  data_type: 'text'
  is_nullable: 1

=head2 san

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 id_code_qualifier

  data_type: 'varchar'
  default_value: 14
  is_nullable: 1
  size: 3

=head2 transport

  data_type: 'varchar'
  default_value: 'FTP'
  is_nullable: 1
  size: 6

=head2 quotes_enabled

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 invoices_enabled

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 orders_enabled

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 shipment_budget

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 order_file_suffix

  data_type: 'varchar'
  is_nullable: 1
  size: 3

=head2 quote_file_suffix

  data_type: 'varchar'
  is_nullable: 1
  size: 3

=head2 invoice_file_suffix

  data_type: 'varchar'
  is_nullable: 1
  size: 3

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 0 },
  "host",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "username",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "password",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "last_activity",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "vendor_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "download_directory",
  { data_type => "text", is_nullable => 1 },
  "upload_directory",
  { data_type => "text", is_nullable => 1 },
  "san",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "id_code_qualifier",
  { data_type => "varchar", default_value => 14, is_nullable => 1, size => 3 },
  "transport",
  { data_type => "varchar", default_value => "FTP", is_nullable => 1, size => 6 },
  "quotes_enabled",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "invoices_enabled",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "orders_enabled",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "shipment_budget",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "order_file_suffix",
  { data_type => "varchar", is_nullable => 1, size => 3 },
  "quote_file_suffix",
  { data_type => "varchar", is_nullable => 1, size => 3 },
  "invoice_file_suffix",
  { data_type => "varchar", is_nullable => 1, size => 3 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 edifact_messages

Type: has_many

Related object: L<Koha::Schema::Result::EdifactMessage>

=cut

__PACKAGE__->has_many(
  "edifact_messages",
  "Koha::Schema::Result::EdifactMessage",
  { "foreign.edi_acct" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shipment_budget

Type: belongs_to

Related object: L<Koha::Schema::Result::Aqbudget>

=cut

__PACKAGE__->belongs_to(
  "shipment_budget",
  "Koha::Schema::Result::Aqbudget",
  { budget_id => "shipment_budget" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "RESTRICT",
    on_update     => "RESTRICT",
  },
);

=head2 vendor

Type: belongs_to

Related object: L<Koha::Schema::Result::Aqbookseller>

=cut

__PACKAGE__->belongs_to(
  "vendor",
  "Koha::Schema::Result::Aqbookseller",
  { id => "vendor_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "RESTRICT",
    on_update     => "RESTRICT",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2015-10-23 11:52:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kdPGCzw9Wn3Wmul3i6aSEA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
