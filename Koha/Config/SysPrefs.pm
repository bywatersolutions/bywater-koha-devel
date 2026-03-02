package Koha::Config::SysPrefs;

# Copyright ByWater Solutions 2014
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;
use YAML::XS qw(LoadFile);

use Koha::Config::SysPref;

use Koha::Config;

use C4::Templates qw(themelanguage);

use base qw(Koha::Objects);

=head1 NAME

Koha::Config::SysPrefs - Koha System Preference object set class

=head1 API

=head2 Instance methods

=head3 get_pref_files

my $files = Koha::config::SysPrefs->get_pref_files();

Return a hashref containing the list of the yml/pref files in admin/preferences

=cut

sub get_pref_files {
    my ( $self, $lang ) = @_;

    my $htdocs = Koha::Config->get_instance->get('intrahtdocs');
    my ($theme) = C4::Templates::themelanguage( $htdocs, 'admin/preferences/admin.pref', 'intranet', undef, $lang );

    my $pref_files = {};
    foreach my $file ( glob("$htdocs/$theme/$lang/modules/admin/preferences/*.pref") ) {
        my ($tab) = ( $file =~ /([a-z0-9_-]+)\.pref$/ );

        # There is a local_use.pref file but it should not be needed
        next if $tab eq 'local_use';
        $pref_files->{$tab} = $file;
    }

    return $pref_files;
}

=head3 get_all_from_yml

my $all_sysprefs = Koha::Config::SysPrefs->get_all_from_yml;

Return the system preferences information contained in the yml/pref files
The result is cached!

eg. for AcqCreateItem
{
    category_name   "Policy",
    choices         {
        cataloguing   "cataloging the record.",
        ordering      "placing an order.",
        receiving     "receiving an order."
    },
    chunks          [
        [0] "Create an item when",
        [1] {
                choices   var{choices},
                pref      "AcqCreateItem"
            },
        [2] "This is only the default behavior, and can be changed per-basket."
    ],
    default         undef,
    description     [
        [0] "Create an item when",
        [1] "This is only the default behavior, and can be changed per-basket."
    ],
    name            "AcqCreateItem",
    tab_id          "acquisitions",
    tab_name        "Acquisitions",
    type            "select"
}

=cut

sub get_all_from_yml {
    my ( $self, $lang ) = @_;

    $lang //= "en";

    my $cache     = Koha::Caches->get_instance("sysprefs");
    my $cache_key = "all:${lang}";
    my $all_prefs = $cache->get_from_cache($cache_key);

    unless ($all_prefs) {

        my $pref_files = Koha::Config::SysPrefs->new->get_pref_files($lang);

        $all_prefs = {};

        while ( my ( $tab, $filepath ) = each %$pref_files ) {
            my $yml = LoadFile($filepath);

            if ( scalar keys %$yml != 1 ) {

                # FIXME Move this to an xt test
                die "malformed pref file ($filepath), only one top level key expected";
            }

            for my $tab_name ( sort keys %$yml ) {
                for my $category_name ( sort keys %{ $yml->{$tab_name} } ) {
                    for my $pref_entry ( @{ $yml->{$tab_name}->{$category_name} } ) {
                        my $pref = {
                            tab_id        => $tab,
                            tab_name      => $tab_name,
                            category_name => $category_name,
                        };
                        for my $entry (@$pref_entry) {
                            push @{ $pref->{chunks} }, $entry;
                            if ( ref $entry ) {

                                # get class if type is not defined
                                # e.g. for OPACHoldsIfAvailableAtPickupExceptions
                                my $type = $entry->{type} || $entry->{class};
                                if ( exists $entry->{choices} ) {
                                    $type = "select";
                                }
                                $type ||= "input";
                                if ( $pref->{name} ) {
                                    push @{ $pref->{grouped_prefs} }, {
                                        name    => $entry->{pref},
                                        choices => $entry->{choices},
                                        default => $entry->{default},
                                        type    => $type,
                                    };
                                    push @{ $pref->{description} }, $entry->{pref};
                                } else {
                                    $pref->{name}    = $entry->{pref};
                                    $pref->{choices} = $entry->{choices};
                                    $pref->{default} = $entry->{default};
                                    $pref->{type}    = $type;
                                }
                            } else {
                                unless ( defined $entry ) {
                                    die sprintf "Invalid description for pref %s", $pref->{name};
                                }
                                push @{ $pref->{description} }, $entry;
                            }
                        }
                        unless ( $pref->{name} ) {

                            # At least one "NOTE:" is expected here
                            next;
                        }
                        $all_prefs->{ $pref->{name} } = $pref;
                        if ( $pref->{grouped_prefs} ) {
                            for my $grouped_pref ( @{ $pref->{grouped_prefs} } ) {
                                $all_prefs->{ $grouped_pref->{name} } = { %$pref, %$grouped_pref };
                            }
                        }
                    }
                }
            }
        }

        $cache->set_in_cache( $cache_key, $all_prefs );
    }
    return $all_prefs;
}

=head2 Class methods

=cut

=head3 _type

=cut

sub _type {
    return 'Systempreference';
}

=head2 object_class

Missing POD for object_class.

=cut

sub object_class {
    return 'Koha::Config::SysPref';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
