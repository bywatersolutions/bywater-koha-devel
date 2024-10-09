package Koha::Schema::Component::Localization;

=head1 NAME

Koha::Schema::Component::Localization

=head1 SYNOPSIS

    package Koha::Schema::Result::SomeTable;

    # ... generated code ...

    __PACKAGE__->load_components('+Koha::Schema::Component::Localization');

    __PACKAGE__->localization_add_relationships(
        'some_table_localizations',
        'some_table_id' => 'some_table_id',
        'first_column',
        'second_column',
        # ...
    );

    package main;

    my $rows = $schema->resultset('SomeTable');
    my $row = $rows->first;
    $row->localizations->search($cond);
    $row->create_related('first_column_localizations', { lang => $lang, translation => $translation })

    while (my $row = $rows->next)
        # first call will fetch all localizations for the current language and
        # the result will be cached, next calls will not execute a query
        $row->localization('first_column', $lang);

        # no query executed
        $row->localization('second_column', $lang);
    }

=head1 DESCRIPTION

This is a DBIx::Class component that helps to manage database localizations by
adding several relationships and methods to a "Result Class"

This can handle several localizable columns (also referred as "properties") per
table

To add database localizations to an existing database table, you need to:

=over

=item * Create a new table with:

=over

=item * An auto incremented column as primary key

=item * A foreign key column referencing the existing table

=item * 3 string (varchar or text) columns named 'property', 'lang',
'translation'

=item * A unique key comprising the foreign key column, 'property' and 'lang'

=back

=item * Regenerate the DBIx::Class schema with
misc/devel/update_dbix_class_files.pl

=item * Add calls to load_components and localization_add_relationships at the
end of the result class

=back

This will give you a relationship named 'localizations' through which you can
access all localizations of a particular table row.

And for every property, you will have:

=over

=item * a "has_many" relationship named <property>_localizations, giving access
to all localizations of a particular table row for this particular property

=item * a "might_have" relationship named <property>_localization, giving
access to the localization of a particular table row for this particular
property and for the current language (uses C4::Languages::getlanguage)

=back

The "row" object will also gain a method C<localization($property, $lang)>
which returns a specific translation and uses cache to avoid executing lots of
queries

=cut

use Modern::Perl;
use Carp;

use base qw(DBIx::Class);

=head2 localization_add_relationships

Add relationships to the localization table

=cut

sub localization_add_relationships {
    my ( $class, $pk_column, @properties ) = @_;

    my $rel_class   = 'Koha::Schema::Result::Localization';
    my $source_name = $class =~ s/.*:://r;

    $class->has_many(
        'localizations',
        $rel_class,
        sub {
            my ($args) = @_;

            return (
                {
                    "$args->{foreign_alias}.code"   => { -ident => "$args->{self_alias}.$pk_column" },
                    "$args->{foreign_alias}.entity" => $source_name,
                },
                !$args->{self_result_object} ? () : {
                    "$args->{foreign_alias}.code"   => $args->{self_result_object}->get_column($pk_column),
                    "$args->{foreign_alias}.entity" => $source_name,
                },
            );
        },
        { cascade_copy => 0, cascade_delete => 1, cascade_update => 0 },
    );

    foreach my $property (@properties) {
        $class->might_have(
            $property . '_localization',
            $rel_class,
            sub {
                my ($args) = @_;

                # Not a 'use' because we don't want to load C4::Languages (and
                # thus C4::Context) while loading the schema
                require C4::Languages;
                my $lang = C4::Languages::getlanguage();

                return (
                    {
                        "$args->{foreign_alias}.code"     => { -ident => "$args->{self_alias}.$pk_column" },
                        "$args->{foreign_alias}.entity"   => $source_name,
                        "$args->{foreign_alias}.property" => $property,
                        "$args->{foreign_alias}.lang"     => $lang,
                    },
                    !$args->{self_result_object} ? () : {
                        "$args->{foreign_alias}.code"     => $args->{self_result_object}->get_column($pk_column),
                        "$args->{foreign_alias}.entity"   => $source_name,
                        "$args->{foreign_alias}.property" => $property,
                        "$args->{foreign_alias}.lang"     => $lang,
                    },
                );
            },
            { cascade_copy => 0, cascade_delete => 0, cascade_update => 0 },
        );

        $class->has_many(
            $property . '_localizations',
            $rel_class,
            sub {
                my ($args) = @_;

                return (
                    {
                        "$args->{foreign_alias}.code"     => { -ident => "$args->{self_alias}.$pk_column" },
                        "$args->{foreign_alias}.entity"   => $source_name,
                        "$args->{foreign_alias}.property" => $property,
                    },
                    !$args->{self_result_object} ? () : {
                        "$args->{foreign_alias}.code"     => $args->{self_result_object}->get_column($pk_column),
                        "$args->{foreign_alias}.entity"   => $source_name,
                        "$args->{foreign_alias}.property" => $property,
                    },
                );
            },
            { cascade_copy => 0, cascade_delete => 0, cascade_update => 0 },
        );
    }
}

sub localization {
    my ( $self, $property, $lang ) = @_;

    my $result_source = $self->result_source;

    my $cache             = Koha::Caches->get_instance('localization');
    my $cache_key         = sprintf( '%s:%s', $result_source->source_name, $lang );
    my $localizations_map = $cache->get_from_cache($cache_key);
    unless ($localizations_map) {
        $localizations_map = {};

        my $localizations = $result_source->schema->resultset('Localization')->search( { lang => $lang } );
        while ( my $localization = $localizations->next ) {
            my $fk               = $localization->get_column('code');
            my $localization_key = sprintf( '%s:%s', $fk, $localization->property );
            $localizations_map->{$localization_key} = $localization->translation;
        }

        $cache->set_in_cache( $cache_key, $localizations_map );
    }

    my ($pk) = $self->id;
    my $localization_key = sprintf( '%s:%s', $pk, $property );

    return $localizations_map->{$localization_key};
}

1;
