package Koha::BackgroundJob::CreateEHoldingsFromBiblios;

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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use JSON qw( decode_json encode_json );
use Try::Tiny;

use Koha::Biblios;
use Koha::DateUtils qw( dt_from_string );
use Koha::ERM::EHoldings::Titles;
use Koha::ERM::EHoldings::Resources;

use C4::Context;

use base 'Koha::BackgroundJob';

=head1 NAME

CreateEHoldingsFromBiblios - Create new eHoldings titles from biblios

This is a subclass of Koha::BackgroundJob.

=head1 API

=head2 Class methods

=head3 job_type

Define the job type of this job.

=cut

sub job_type {
    return 'create_eholdings_from_biblios';
}

=head3 process

Process the import.

=cut

sub process {
    my ( $self, $args ) = @_;

    if ( $self->status eq 'cancelled' ) {
        return;
    }

    my $job_progress = 0;
    $self->started_on(dt_from_string)
        ->progress($job_progress)
        ->status('started')
        ->store;

    my @messages;
    my @record_ids = @{ $args->{record_ids} };
    my $package_id = $args->{package_id};

    my $package = Koha::ERM::EHoldings::Packages->find($package_id);
    unless ( $package ) {
        push @messages, {
            type => 'error',
            code => 'package_do_not_exist',
            package_id => $package_id,
        };
    }

    my $report = {
        total_records => scalar @record_ids,
        total_success => 0,
    };
    my $fix_coverage = sub {
        my $coverage = shift || q{};
        my @coverages = split '-', $coverage;
        return ($coverages[0], (@coverages > 1 ? $coverages[1] : q{}));
    };

    my %existing_biblio_ids = map {
        my $resource = $_;
        map { $_->biblio_id => $resource->resource_id } $resource->title
    } $package->resources->as_list;

    RECORD_IDS: for my $biblio_id ( sort { $a <=> $b } @record_ids ) {

        last if $self->get_from_storage->status eq 'cancelled';

        next unless $biblio_id;

        try {
            if ( grep { $_ eq $biblio_id } keys %existing_biblio_ids ) {
                push @messages,
                  {
                    type        => 'warning',
                    code        => 'biblio_already_exists',
                    biblio_id   => $biblio_id,
                    resource_id => $existing_biblio_ids{$biblio_id},
                  };
                return;
            }
            my $biblio = Koha::Biblios->find($biblio_id);
            my $record = $biblio->metadata->record;
            my $publication_title = $biblio->title;
            my $print_identifier =
                 $record->subfield( '020', 'a' )
              || $record->subfield( '020', 'z' )
              || $record->subfield( '022', 'a' )
              || $record->subfield( '022', 'y' );
            my $online_identifier = $print_identifier;
            my ( $date_first_issue_online, $date_last_issue_online ) =
              $fix_coverage->( $record->subfield( '866', 'a' ) );
            my ( $num_first_vol_online, $num_last_vol_online ) =
              $fix_coverage->( $record->subfield( '863', 'a' ) );
            my ( $num_first_issue_online, $num_last_issue_online ) =
              ( '', '' );    # FIXME ?
            my $title_url = $record->subfield( '856', 'u' );
            my $first_author = $biblio->author;
            my $embargo_info     = '';                                 # FIXME ?
            my $coverage_depth   = $title_url ? 'fulltext' : 'print';
            my $notes            = $record->subfield( '852', 'z' );
            my $publisher_name   = $record->subfield( '260', 'b' );
            my $publication_type = '';                                 # FIXME ?
            my $date_monograph_published_print  = '';                  # FIXME ?
            my $date_monograph_published_online = '';                  # FIXME ?
            my $monograph_volume                = '';                  # FIXME ?
            my $monograph_edition               = '';                  # FIXME ?
            my $first_editor                    = '';                  # FIXME ?
            my $parent_publication_title_id     = '';                  # FIXME ?
            my $preceeding_publication_title_id = '';                  # FIXME ?
            my $access_type                     = '';                  # FIXME ?

            my $eholding_title = {
                biblio_id                       => $biblio_id,
                publication_title               => $publication_title,
                print_identifier                => $print_identifier,
                online_identifier               => $online_identifier,
                date_first_issue_online         => $date_first_issue_online,
                num_first_vol_online            => $num_first_vol_online,
                num_first_issue_online          => $num_first_issue_online,
                date_last_issue_online          => $date_last_issue_online,
                num_last_vol_online             => $num_last_vol_online,
                num_last_issue_online           => $num_last_issue_online,
                title_url                       => $title_url,
                first_author                    => $first_author,
                embargo_info                    => $embargo_info,
                coverage_depth                  => $coverage_depth,
                notes                           => $notes,
                publisher_name                  => $publisher_name,
                publication_type                => $publication_type,
                date_monograph_published_print  => $date_monograph_published_print,
                date_monograph_published_online => $date_monograph_published_online,
                monograph_volume                => $monograph_volume,
                monograph_edition               => $monograph_edition,
                first_editor                    => $first_editor,
                parent_publication_title_id     => $parent_publication_title_id,
                preceeding_publication_title_id => $preceeding_publication_title_id,
                access_type                     => $access_type,
              };
              $eholding_title = Koha::ERM::EHoldings::Title->new($eholding_title)->store;
              Koha::ERM::EHoldings::Resource->new({ title_id => $eholding_title->title_id, package_id => $package_id })->store;

            $report->{total_success}++;
        } catch {
            push @messages, {
                type => 'error',
                code => 'eholding_not_created',
                error => $_,
            };
        };
        $self->progress( ++$job_progress )->store;
    }

    my $job_data = decode_json $self->data;
    $job_data->{messages} = \@messages;
    $job_data->{report} = $report;

    $self->ended_on(dt_from_string)
        ->data(encode_json $job_data);
    $self->status('finished') if $self->status ne 'cancelled';
    $self->store;
}

=head3 enqueue

Enqueue the new job

=cut

sub enqueue {
    my ( $self, $args) = @_;

    return unless exists $args->{package_id};
    return unless exists $args->{record_ids};

    $self->SUPER::enqueue({
        job_size  => scalar @{$args->{record_ids}},
        job_args  => $args,
        job_queue => 'long_tasks',
    });
}

=head3 additional_report

=cut

sub additional_report {
    my ($self) = @_;

    my $loggedinuser = C4::Context->userenv ? C4::Context->userenv->{'number'} : undef;
    return {};
}

1;
