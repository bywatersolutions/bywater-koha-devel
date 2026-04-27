package Koha::Exceptions::Report;

use Modern::Perl;

use Exception::Class (
    'Koha::Exceptions::Report'                   => { description => "Something went wrong!" },
    'Koha::Exceptions::Report::DuplicateRunning' => {
        isa         => 'Koha::Exceptions::Report',
        description => "The configured per-user limit on simultaneous runs of this report has been reached",
        fields      => [ 'report_id', 'user_id', 'limit' ],
    },
);

1;
