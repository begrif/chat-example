#!/usr/bin/perl -w
use strict;
use Socket;
my ($remote, $port, $iaddr, $paddr, $proto, $line);
my ($timeout, $got_timeout);

$remote  = shift || "localhost";
$port    = shift || 2345;  # random port

$timeout = 1;

if ($port =~ /\D/) { $port = getservbyname($port, "tcp") }
die "No port" unless $port;
$iaddr   = inet_aton($remote)       || die "no host: $remote";
$paddr   = sockaddr_in($port, $iaddr);

$proto   = getprotobyname("tcp");
socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
connect(SOCK, $paddr)               || die "connect: $!";

select(SOCK);
$| = 1;
select(STDOUT);
$| = 1;

sub ALARM { $got_timeout = 1; }
$SIG{ALRM} = \&ALARM;

for ( ;; ) {
  alarm $timeout;

  $line = <SOCK>;
  if (length($line)) {
      print $line;
  } else {
    alarm $timeout;
  }

  $line = <STDIN>;
  if (length($line)) {
      print SOCK $line;
  }
}

close (SOCK)                        || die "close: $!";

