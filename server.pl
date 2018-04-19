#!/usr/bin/perl -Tw
use strict;
BEGIN { $ENV{PATH} = "/usr/bin:/bin" }
use Socket;
use POSIX;
use Time::HiRes qw( alarm );

my $EOL = "\015\012";
my @chatters;
my $got_timeout = 'timeout!';
my $timeout = 0.0100; # microseconds
my $closed;

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

sub ALARM { die "$got_timeout\n" }
sub CATCHPIPE { $closed = 1; die "sigpipe\n" }
$SIG{PIPE} = \&CATCHPIPE;

# main loop
#	checks for new connections (with timeout)
#		sends welcome to new user
#	checks for new messages from all existing connections (with timeout)
#		forwards messages to all other users
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
      write_with_protection(*Client, "Hello there. Your first entry should be your username$EOL");
    }
  } # if new client
  
  if ($@ and $@ !~ /$got_timeout/) { die "Issue in accept(): $@\n"; }

  my $gone = 0;
  for my $ch (@chatters) {
    my $handle = $$ch{fh};
    my $in = read_with_timout($handle);
    if (length($in)) {
       my $send;

       $in =~ s/^\s*//;
       $in =~ s/\s*$//;

       if(length($in)) {
         logmsg "got $$ch{port} message: $in";
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
           write_with_protection($outhandle, $send);
	   if($closed) {
	     logmsg("lost user on $$ls{port}");
	     $$ls{closed} = 1;
	     $gone ++;
	   }
	 }
	 $$ch{sender} = undef;

      } # got something to share
    }
  } # check for chat messages

  # prune dead users
  if($gone) {
     my @new_list;
     for my $ch (@chatters) {
       push(@new_list, $ch) unless $$ch{closed};
     }
     @chatters = @new_list;
  }
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
  $closed = undef;
  eval {
         $rv = syswrite $fh, $msg;
       };
  if ($@ and $closed) { logmsg("socket closed")}
  if (!defined($rv)) { $closed = 1; logmsg("write failed: $!"); }
}
