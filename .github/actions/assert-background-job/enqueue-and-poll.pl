#!/usr/bin/perl
use strict;
use warnings;
use Koha::Database;
use C4::Context;
use Net::Stomp;
use JSON qw( encode_json );
use Encode;

my $queue   = $ARGV[0] // 'default';
my $timeout = $ARGV[1] // 60;

# Insert a background_jobs row by hand and publish a matching STOMP
# message to the RabbitMQ queue, mirroring Koha::BackgroundJob::enqueue
# but with a synthetic job type. The worker will pull it, fail to map
# 'ci_systemd_noop' to a handler class, and mark the row as
# 'failed' or 'cancelled' — which is exactly what we want as a
# liveness signal: status moves off 'new'.
my $schema = Koha::Database->new->schema;

# Payload that won't crash a real consumer when it tries to process.
# - workers (default / long_tasks): expect a registered Koha::BackgroundJob
#   subclass by type; ours isn't registered, so the worker marks status
#   'failed' (which is fine — status leaves 'new').
# - es_indexer_daemon: doesn't dispatch on type. It blindly derefs
#   $args->{record_ids}, so we have to give it an empty array of records
#   to keep it from dying on `@{undef}`. record_server picks the biblio
#   or authority indexer downstream — biblioserver is the default.
my $data = $queue eq 'elastic_index'
    ? '{"record_server":"biblioserver","record_ids":[]}'
    : '{}';

my $job = $schema->resultset('BackgroundJob')->create(
    {   type        => 'ci_systemd_noop',
        status      => 'new',
        queue       => $queue,
        size        => 1,
        data        => $data,
        context     => '{}',
        enqueued_on => \"NOW()",
    }
);
my $job_id = $job->id;
print "Inserted background_jobs row id=$job_id queue=$queue data=$data\n";

my $config = C4::Context->config('message_broker') // {};
my $host   = $config->{hostname} // 'localhost';
my $port   = $config->{port}     // 61613;
my $user   = $config->{username} // 'guest';
my $pass   = $config->{password} // 'guest';

my $stomp = Net::Stomp->new( { hostname => $host, port => $port } );
my $frame = $stomp->connect( { login => $user, passcode => $pass } );
die "STOMP connect failed: " . $frame->body
    unless $frame->command eq 'CONNECTED';

my $namespace   = C4::Context->config('memcached_namespace');
my $destination = "/queue/${namespace}-${queue}";
my $body        = encode_json( { job_id => $job_id } );

$stomp->send(
    {   destination    => $destination,
        body           => Encode::encode_utf8($body),
        persistent     => 'true',
        'content-type' => 'application/json',
    }
);
print "Published STOMP message to $destination (job_id=$job_id)\n";

my $start = time;
my $last_status;
while ( time - $start < $timeout ) {
    my $row = $schema->resultset('BackgroundJob')->find($job_id)
        or die "job $job_id disappeared from background_jobs\n";
    my $status = $row->status;
    if ( $status ne ( $last_status // '' ) ) {
        printf "  t=%2ds status=%s\n", time - $start, $status;
        $last_status = $status;
    }
    if ( $status ne 'new' ) {

        # Give the worker a small grace window to reach a terminal
        # status before reporting back.
        sleep 3;
        my $final = $schema->resultset('BackgroundJob')->find($job_id);
        my $fs    = $final->status;
        print "Final status after grace: $fs\n";

        # Any non-'new' status proves the worker pulled and processed
        # (or failed gracefully on) the message — which is exactly
        # the daemon-is-alive signal we're after.
        print "Worker for queue '$queue' picked up job $job_id (status=$fs) — worker is alive\n";
        exit 0;
    }
    sleep 1;
}

die "Worker for queue '$queue' did not pick up job $job_id in ${timeout}s "
    . "(status still 'new'). Worker may be down or not consuming from RabbitMQ. "
    . "destination='$destination' broker=$host:$port login=$user\n";
