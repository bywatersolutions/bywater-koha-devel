package Koha::BackgroundJob::UpdateElasticPatronIndex;

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

use Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

use base 'Koha::BackgroundJob';

=head1 NAME

Koha::BackgroundJob::UpdateElasticPatronIndex - Index patrons in Elasticsearch

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type {
    return 'update_elastic_patron_index';
}

=head3 process

Process the job: index the patron records.

=cut

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my $patron_ids = $args->{patron_ids};

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();
    $indexer->index_patrons($patron_ids);

    $self->finish;
}

=head3 enqueue

Enqueue the new job

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    return unless exists $args->{patron_ids};

    $self->SUPER::enqueue(
        {
            job_size  => 1,
            job_args  => { patron_ids => $args->{patron_ids} },
            job_queue => 'elastic_index',
        }
    );
}

1;
