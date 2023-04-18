use utf8;
package Koha::Schema::Result::Letter;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::Letter

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<letter>

=cut

__PACKAGE__->table("letter");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

primary key identifier

=head2 module

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

Koha module that triggers this notice or slip

=head2 code

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

unique identifier for this notice or slip

=head2 branchcode

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 10

the branch this notice or slip is used at (branches.branchcode)

=head2 name

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 100

plain text name for this notice or slip

=head2 is_html

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 1

does this notice or slip use HTML (1 for yes, 0 for no)

=head2 title

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 200

subject line of the notice

=head2 content

  data_type: 'mediumtext'
  is_nullable: 1

body text for the notice or slip

=head2 message_transport_type

  data_type: 'varchar'
  default_value: 'email'
  is_foreign_key: 1
  is_nullable: 0
  size: 20

transport type for this notice

=head2 lang

  data_type: 'varchar'
  default_value: 'default'
  is_nullable: 0
  size: 25

lang of the notice

=head2 updated_on

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

last modification

=head2 font_size

  data_type: 'integer'
  default_value: 14
  is_nullable: 0

font size used when notice is printed

=head2 text_justify

  data_type: 'enum'
  default_value: 'L'
  extra: {list => ["L","C","R"]}
  is_nullable: 0

text justification used when notice is printed

=head2 units

  data_type: 'enum'
  default_value: 'INCH'
  extra: {list => ["POINT","INCH","MM","CM"]}
  is_nullable: 0

units to use for print measurements

=head2 notice_width

  data_type: 'float'
  default_value: 8.5
  is_nullable: 0

width of notice

=head2 top_margin

  data_type: 'float'
  default_value: 0
  is_nullable: 0

top margin for notice

=head2 left_margin

  data_type: 'float'
  default_value: 0
  is_nullable: 0

left margin for notice

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "module",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "code",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "branchcode",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 10 },
  "name",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 100 },
  "is_html",
  { data_type => "tinyint", default_value => 0, is_nullable => 1 },
  "title",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 200 },
  "content",
  { data_type => "mediumtext", is_nullable => 1 },
  "message_transport_type",
  {
    data_type => "varchar",
    default_value => "email",
    is_foreign_key => 1,
    is_nullable => 0,
    size => 20,
  },
  "lang",
  {
    data_type => "varchar",
    default_value => "default",
    is_nullable => 0,
    size => 25,
  },
  "updated_on",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "font_size",
  { data_type => "integer", default_value => 14, is_nullable => 0 },
  "text_justify",
  {
    data_type => "enum",
    default_value => "L",
    extra => { list => ["L", "C", "R"] },
    is_nullable => 0,
  },
  "units",
  {
    data_type => "enum",
    default_value => "INCH",
    extra => { list => ["POINT", "INCH", "MM", "CM"] },
    is_nullable => 0,
  },
  "notice_width",
  { data_type => "float", default_value => 8.5, is_nullable => 0 },
  "top_margin",
  { data_type => "float", default_value => 0, is_nullable => 0 },
  "left_margin",
  { data_type => "float", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<letter_uniq_1>

=over 4

=item * L</module>

=item * L</code>

=item * L</branchcode>

=item * L</message_transport_type>

=item * L</lang>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "letter_uniq_1",
  ["module", "code", "branchcode", "message_transport_type", "lang"],
);

=head1 RELATIONS

=head2 message_queues

Type: has_many

Related object: L<Koha::Schema::Result::MessageQueue>

=cut

__PACKAGE__->has_many(
  "message_queues",
  "Koha::Schema::Result::MessageQueue",
  { "foreign.letter_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 message_transport_type

Type: belongs_to

Related object: L<Koha::Schema::Result::MessageTransportType>

=cut

__PACKAGE__->belongs_to(
  "message_transport_type",
  "Koha::Schema::Result::MessageTransportType",
  { message_transport_type => "message_transport_type" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2023-04-27 04:16:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6UU3qiPymxx0QY3G9SvD2Q

sub koha_object_class {
    'Koha::Notice::Template';
}
sub koha_objects_class {
    'Koha::Notice::Templates';
}

1;
