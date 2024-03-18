use utf8;
package Koha::Schema::Result::FileAccessAccount;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::FileAccessAccount

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<file_access_accounts>

=cut

__PACKAGE__->table("file_access_accounts");

=head1 ACCESSORS

=head2 code

  data_type: 'varchar'
  is_nullable: 0
  size: 20

Unique code for this given server for use in cli parameters

=head2 description

  data_type: 'mediumtext'
  is_nullable: 0

=head2 transport

  data_type: 'varchar'
  default_value: 'FTP'
  is_nullable: 1
  size: 6

=head2 host

  data_type: 'varchar'
  default_value: 'localhost'
  is_nullable: 0
  size: 80

=head2 username

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 password

  data_type: 'mediumtext'
  is_nullable: 1

=head2 debug

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "code",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "description",
  { data_type => "mediumtext", is_nullable => 0 },
  "transport",
  { data_type => "varchar", default_value => "FTP", is_nullable => 1, size => 6 },
  "host",
  {
    data_type => "varchar",
    default_value => "localhost",
    is_nullable => 0,
    size => 80,
  },
  "username",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "password",
  { data_type => "mediumtext", is_nullable => 1 },
  "debug",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->set_primary_key("code");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-03-18 17:31:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3PRUk5mCynwI9ol4tekwug

__PACKAGE__->add_columns(
    '+debug' => { is_boolean => 1 },
);

sub koha_objects_class {
    'Koha::File::Access::Accounts';
}

sub koha_object_class {
    'Koha::File::Access::Account';
}

1;
