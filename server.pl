#!/usr/bin/perl -Tw
use strict;
BEGIN { $ENV{PATH} = "/usr/bin:/bin" }
use Socket;
use POSIX;
use Carp;
my $EOL = "\015\012";
my @chatters;
my $got_timeout = 'timeout!';
my $timeout = 1;

sub logmsg { print "$0 $$: @_ at ", scalar localtime(), "\n" }

my $port  = shift || 2345;
if ($port =~ /^(\d+)$/x) {
  $port = $1; # untainted
}

my $proto = getprotobyname("tcp");

socket(Server, PF_INET, SOCK_STREAM, $proto)    || die "socket: $!";
setsockopt(Server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
						|| die "setsockopt: $!";
bind(Server, sockaddr_in($port, INADDR_ANY))    || die "bind: $!";
listen(Server, SOMAXCONN)                       || die "listen: $!";

# turn on autoflush on socket and STDOUT
select(Server);
$| = 1;
select(STDOUT);
$| = 1;

logmsg "server started on port $port";

# $SIG{CHLD} = \&REAPER;
sub ALARM { die "$got_timeout\n" }

for ( ;; ) {
  # new version of $paddr and Client every time through
  my $paddr;
  local *Client;

  if ( $paddr = accept_with_timeout(*Client, *Server) ) {
    if( $! != EINTR ) {
      my($port, $iaddr) = sockaddr_in($paddr);
      my $name = gethostbyaddr($iaddr, AF_INET);

      # turn on autoflush for client
      select(Client);
      $| = 1;
      select(STDOUT);

      push(@chatters, {
	    port   => $port,
	    iaddr  => $iaddr,
	    paddr  => $paddr,
	    fh     => *Client,
	    user   => undef,
	    sender => undef,
	  });


      logmsg "connection from $name [", inet_ntoa($iaddr), "] at port $port";
      print Client "Hello there. Your first entry should be your username$EOL";
    }
  } # if new client
  
  if ($@ and $@ !~ /$got_timeout/) { die "Issue in accept(): $@\n"; }

  for my $ch (@chatters) {
    my $handle = $$ch{fh};
    my $in = read_with_timout($handle);
    if (length($in)) {
       logmsg "got $$ch{port} message: $in";
       my $send;

       $in =~ s/^\s*//;
       $in =~ s/\s*$//;

       if(length($in)) {
	 if(!defined($$ch{user})) {
	   $$ch{user} = $in;

	   $send = "User $in joined the chat$EOL";
	 } else {
	   $send = $$ch{user} . ': ' . $in . $EOL;
	 }

	 # send out message to all other listeners
	 $$ch{sender} = 1;
	 for my $ls (@chatters) {
	   next if $$ls{sender};
	   my $outhandle = $$ls{fh};
	   print $outhandle $send;
	 }
	 $$ch{sender} = undef;

      } # got something to share
    }
  } # check for chat messages
}

# accept wrapper that uses a timeout to avoid perpetual blocking
sub accept_with_timeout {
  my $C = shift;
  my $S = shift;
  my $paddr;
  eval {
        local $SIG{ALRM} = \&ALARM;
        alarm $timeout;
        $paddr = accept($C, $S);
        alarm 0;
       };
  if ($@ and $@ !~ /$got_timeout/) { logmsg("during accept: $@\n") }
  return $paddr;
} # end &accept_with_timeout

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

