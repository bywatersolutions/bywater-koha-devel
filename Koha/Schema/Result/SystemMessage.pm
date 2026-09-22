use utf8;
package Koha::Schema::Result::SystemMessage;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::SystemMessage

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<system_messages>

=cut

__PACKAGE__->table("system_messages");

=head1 ACCESSORS

=head2 system_message_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

primary key

=head2 component

  data_type: 'varchar'
  is_nullable: 0
  size: 80

area of Koha that reported the message

=head2 message

  data_type: 'mediumtext'
  is_nullable: 0

message text

=head2 occurrences

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

number of times this message has been reported since it was first seen

=head2 created_date

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

when this message was first reported

=head2 updated_date

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

when this message was last reported

=head2 cleared_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

when this message was cleared, NULL while it is still showing

=cut

__PACKAGE__->add_columns(
  "system_message_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "component",
  { data_type => "varchar", is_nullable => 0, size => 80 },
  "message",
  { data_type => "mediumtext", is_nullable => 0 },
  "occurrences",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
  "created_date",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "updated_date",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "cleared_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</system_message_id>

=back

=cut

__PACKAGE__->set_primary_key("system_message_id");


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-09-22 19:05:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kZ63UHD3HC/fnho112g6ZA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
