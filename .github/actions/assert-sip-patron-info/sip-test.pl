#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use POSIX qw(strftime);

my ( $host, $port, $sip_user, $sip_pass, $barcode, $institution ) = @ARGV;
$host        ||= '127.0.0.1';
$port        ||= 6001;
$institution ||= '';
die "usage: sip-test.pl HOST PORT USER PASS BARCODE [INSTITUTION]\n"
    unless $sip_user && $sip_pass && $barcode;

my $sock = IO::Socket::INET->new(
    PeerAddr => $host,
    PeerPort => $port,
    Proto    => 'tcp',
    Timeout  => 30,
) or die "can't connect to $host:$port: $!\n";
$sock->autoflush(1);

# SIP2 checksum: sum of all bytes (mod 65536), then negated. Always
# include AY<seq>AZ<XXXX> at the end — error-detect-enabled servers
# require it, error-detect-disabled servers ignore it.
sub sip_checksum {
    my ($msg) = @_;
    my $sum = 0;
    $sum += ord $_ for split //, $msg;
    return sprintf '%04X', ( -$sum ) & 0xFFFF;
}

my $seq = 0;
sub exchange {
    my ( $s, $msg, $label ) = @_;
    my $partial = $msg . "AY${seq}AZ";
    my $full    = $partial . sip_checksum($partial);
    $seq = ( $seq + 1 ) % 10;
    print $s "$full\r";

    my ( $buf, $resp ) = ( '', '' );
    while ( my $n = sysread $s, $buf, 4096 ) {
        $resp .= $buf;
        last if $resp =~ /\r/;
    }
    $resp =~ s/\r.*//s;
    print "  $label request : $full\n";
    print "  $label response: $resp\n";
    return $resp;
}

# 93 login: 93 + UID-algo(0=plain) + PWD-algo(0=plain) +
#           CN<user>| + CO<pass>| + CP<terminal/institution>|
my $login_msg = "9300CN${sip_user}|CO${sip_pass}|CP${institution}|";
my $login_resp = exchange( $sock, $login_msg, '93 login' );
die "SIP 93 login failed: response was '$login_resp' (expected '941...')\n"
    unless $login_resp =~ /^941/;
print "✓ SIP 93 login OK\n";

# 63 patron information:
#   63 + language(3) + transaction_date(18) + summary(10) +
#   AO<inst>| + AA<patron>| + AC<term_pw>|
my $tx_date = strftime '%Y%m%d    %H%M%S', localtime;
my $summary = ' ' x 10;
my $info_msg
    = "63001${tx_date}${summary}AO${institution}|AA${barcode}|AC|";
my $info_resp = exchange( $sock, $info_msg, '63 patron info' );
die "SIP 63 reply not a 64 response: '$info_resp'\n"
    unless $info_resp =~ /^64/;

my ($valid) = $info_resp =~ /\|BL([YN])/;
die "SIP 64 response missing BL (valid_patron) field: '$info_resp'\n"
    unless defined $valid;
die "SIP patron $barcode reported invalid (BL=$valid)\n"
    unless $valid eq 'Y';

my ($name) = $info_resp =~ /\|AE([^|]*)/;
die "SIP 64 response missing AE (personal_name): '$info_resp'\n"
    unless defined $name && length $name;

print "✓ SIP 63 patron info OK — barcode=$barcode name='$name' BL=$valid\n";
close $sock;
