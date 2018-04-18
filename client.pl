#!/usr/bin/perl -w
use strict;
use Socket;
my ($remote, $port, $iaddr, $paddr, $proto, $line);
my ($timeout, $got_timeout);

$remote  = shift || "localhost";
$port    = shift || 2345;  # random port

$got_timeout = 'timeout!';
$timeout = 1;
sub ALARM { die "$got_timeout\n" }

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

for ( ;; ) {

  $line = read_with_timout(*SOCK);
  if (length($line)) {
      print $line;
  }

  $line = read_with_timout(*STDIN);
  if (length($line)) {
      print SOCK $line;
  }
}

close (SOCK)                        || die "close: $!";

# read wrapper that uses a timeout to avoid perpetual blocking
sub read_with_timout {
  my $fh = shift;
  my $line;
  eval {
        local $SIG{ALRM} = \&ALARM;
        alarm $timeout;
        $line = <$fh>;
        alarm 0;
       };
  if ($@ and $@ !~ /$got_timeout/) { logmsg("during socket read: $@\n")}
  return $line;
} # end &read_with_timout

