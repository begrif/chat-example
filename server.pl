#!/usr/bin/perl -Tw
use strict;
BEGIN { $ENV{PATH} = "/usr/bin:/bin" }
use Socket;
use POSIX;
use Carp;
my $EOL = "\015\012";
my $got_timeout = 0;
my @chatters;
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

logmsg "server started on port $port";

my $paddr;
sub ALARM { $got_timeout = 1; }
# $SIG{CHLD} = \&REAPER;
$SIG{ALRM} = \&ALARM;


for ( ;; ) {
  alarm $timeout;

  if ( $paddr = accept(Client, Server) ) {
    select(Client);
    $| = 1;
    select(Server);
    $| = 1;
    select(STDOUT);

    if( $! != EINTR ) {
      my %client;
      my($port, $iaddr) = sockaddr_in($paddr);
      my $name = gethostbyaddr($iaddr, AF_INET);

      %client = (
	  port => $port,
	  iaddr => $iaddr,
	  paddr => $paddr,
	  fh => *Client,
	  user => undef,
       );

      push(@chatters, \%client);

      logmsg "connection from $name [", inet_ntoa($iaddr), "] at port $port";
      print Client "Hello there. Your first entry should be your username$EOL";
    } else {
      # reset alarm because it went off
      alarm $timeout;
    }
  } # if new client

  for my $ch (@chatters) {
    my $handle = $$ch{fh};
    my $in = <$handle>;
    if (length($in)) {
       logmsg "got $$ch{port} message: $in";
       my $send;

       $in =~ s/^\s*//;
       $in =~ s/\s*$//;

       if(!defined($$ch{user}) and length($in)) {
          $$ch{user} = $in;

	  $send = "User $in joined the chat$EOL";
       } else {
         $send = $in . $EOL;
       }

       $$ch{sender} = 1;
       for my $ls (@chatters) {
         next if $$ls{sender};
         my $outhandle = $$ls{fh};
	 print $outhandle $send;
       }
       $$ch{sender} = undef;

    }
  }
}

