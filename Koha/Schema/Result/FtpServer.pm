use utf8;
package Koha::Schema::Result::FtpServer;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::FtpServer

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<ftp_servers>

=cut

__PACKAGE__->table("ftp_servers");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 code

  data_type: 'varchar'
  is_nullable: 0
  size: 20

Unique code for this given server for use in cli parameters

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 80

=head2 host

  data_type: 'varchar'
  default_value: 'localhost'
  is_nullable: 0
  size: 80

=head2 port

  data_type: 'integer'
  default_value: 25
  is_nullable: 0

=head2 timeout

  data_type: 'integer'
  default_value: 120
  is_nullable: 0

=head2 type

  data_type: 'enum'
  extra: {list => ["ftp","sftp"]}
  is_nullable: 0

=head2 user_name

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 password

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 debug

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "code",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 80 },
  "host",
  {
    data_type => "varchar",
    default_value => "localhost",
    is_nullable => 0,
    size => 80,
  },
  "port",
  { data_type => "integer", default_value => 25, is_nullable => 0 },
  "timeout",
  { data_type => "integer", default_value => 120, is_nullable => 0 },
  "type",
  {
    data_type => "enum",
    extra => { list => ["ftp", "sftp"] },
    is_nullable => 0,
  },
  "user_name",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "password",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "debug",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<code>

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->add_unique_constraint("code", ["code"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-02-26 16:51:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ZHcUttrXhvHzQNo76KB8BA

__PACKAGE__->add_columns(
    '+debug' => { is_boolean => 1 },
);

sub koha_objects_class {
    'Koha::File::Transport::Servers';
}

sub koha_object_class {
    'Koha::File::Transport::Server';
}

1;
