#!/usr/bin/perl -w
use strict;
use Socket;
use Time::HiRes qw( alarm time );

my ($remote, $port, $iaddr, $paddr, $proto, $line);
my ($timeout, $got_timeout, $closed, $EOL, $socket_time);

$remote  = shift || "localhost";
$port    = shift || 2345;  # random port

$EOL = "\015\012";
$got_timeout = 'timeout!';
$timeout = 0.0100; # microseconds
$closed = undef;

sub logmsg { print "$0 $$: @_ at ", scalar localtime(), "\n" }

sub ALARM { die "$got_timeout\n" }
sub CATCHPIPE { $closed = 1; die "sigpipe\n" }
$SIG{PIPE} = \&CATCHPIPE;

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

$socket_time = time();
for ( ;; ) {

  $line = read_with_timout(*SOCK);
  if (length($line)) {
      print $line;
      $socket_time = time();
  }

  $line = read_with_timout(*STDIN);
  if (length($line)) {
      $line =~ s/\s+$//;
      write_with_protection(*SOCK, $line . $EOL);
      $socket_time = time();
  }

  # send null message to the server to make sure it's still alive
  if ((100 * $timeout) > (time() - $socket_time)) {
      write_with_protection(*SOCK, $EOL);
      $socket_time = time();
  }

  last if $closed;
}

print "Connection shut down.\n";
close (SOCK);
exit;

# read wrapper that uses a timeout to avoid perpetual blocking
sub read_with_timout {
  my $fh = shift;
  my $line;
  my $rv;
  eval {
        local $SIG{ALRM} = \&ALARM;
        alarm $timeout;
	# try to read a big number of bytes, expect to get much less
        $rv = sysread $fh, $line, 9999;
        alarm 0;
       };
  if ($@ and $@ !~ /$got_timeout/) { logmsg("during socket read: $@") }
  # error code 4: interrupted syscall (eg, alarm went off)
  if (!defined($rv) and 4 != 0+$!) { $closed = 1; logmsg("read failed: $!"); return ''; }
  return $line;
} # end &read_with_timout

# capture SIGPIPE errors
sub write_with_protection {
  my $fh = shift;
  my $msg = shift;
  my $rv;
  eval {
         $rv = syswrite $fh, $msg;
       };
  if ($@ and $closed) { logmsg("socket closed")}
  if (!defined($rv)) { $closed = 1; logmsg("write failed: $!"); }
}
