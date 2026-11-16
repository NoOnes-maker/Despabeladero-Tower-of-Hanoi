#!/usr/bin/env perl
# Tiny static web server for the Towers of Hanoi simulator.
# Core Perl only (IO::Socket::INET) - nothing to install from CPAN.
#
#   perl server.pl                 -> http://127.0.0.1:8080  (this machine only)
#   perl server.pl --public        -> listens on 0.0.0.0     (anyone on your LAN/Wi-Fi)
#   perl server.pl --port 3000
use strict;
use warnings;
use IO::Socket::INET;
use Getopt::Long;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $port = 8080;
my $public = 0;
GetOptions('port=i' => \$port, 'public' => \$public) or die "usage: $0 [--port N] [--public]\n";

my $root = abs_path(dirname(abs_path($0)));
my $host = $public ? '0.0.0.0' : '127.0.0.1';

my %MIME = (
    html => 'text/html; charset=utf-8', css => 'text/css; charset=utf-8',
    js   => 'application/javascript; charset=utf-8', json => 'application/json',
    png  => 'image/png', jpg => 'image/jpeg', svg => 'image/svg+xml', ico => 'image/x-icon',
    pl   => 'text/plain; charset=utf-8', txt => 'text/plain; charset=utf-8',
    wav  => 'audio/wav', mp3 => 'audio/mpeg',
);

my $srv = IO::Socket::INET->new(
    LocalAddr => $host, LocalPort => $port, Proto => 'tcp',
    Listen => 20, ReuseAddr => 1,
) or die "Cannot listen on $host:$port - $!\n";

$SIG{CHLD} = 'IGNORE';   # auto-reap forked children
$SIG{PIPE} = 'IGNORE';

print "Towers of Hanoi server running (Perl $^V)\n";
print "  Local:   http://localhost:$port/\n";
if ($public) {
    print "  Network: http://<your-LAN-IP>:$port/   (find IP with: hostname -I)\n";
    print "  Internet: expose it with a tunnel, e.g.  cloudflared tunnel --url http://localhost:$port\n";
}
print "Ctrl+C to stop.\n";

while (my $c = $srv->accept) {
    my $pid = fork();
    next unless defined $pid;
    if ($pid) { close $c; next; }
    close $srv;
    handle($c);
    close $c;
    exit 0;
}

sub respond {
    my ($c, $code, $msg, $type, $body, $head) = @_;
    print $c "HTTP/1.1 $code $msg\r\nContent-Type: $type\r\nContent-Length: ", length($body),
             "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n";
    print $c $body unless $head;
}

sub handle {
    my $c = shift;
    $c->autoflush(1);
    local $SIG{ALRM} = sub { exit 0 };
    alarm 10;
    my $line = <$c>;
    return unless defined $line;
    while (my $h = <$c>) { last if $h =~ /^\r?\n$/ }   # discard headers
    alarm 0;
    my ($method, $uri) = $line =~ m{^(\w+)\s+(\S+)};
    return respond($c, 400, 'Bad Request', 'text/plain', "Bad request\n") unless $method;
    return respond($c, 405, 'Method Not Allowed', 'text/plain', "GET/HEAD only\n")
        unless $method eq 'GET' || $method eq 'HEAD';

    (my $path = $uri) =~ s/[?#].*//;
    $path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $path = '/index.html' if $path eq '/';

    my $file = abs_path("$root$path");
    # block path traversal and only serve safe static types
    if (!defined $file || index($file, "$root/") != 0 || !-f $file
        || $file =~ m{/server\.pl$} || $file =~ m{/\.}) {
        return respond($c, 404, 'Not Found', 'text/plain', "404 Not Found\n", $method eq 'HEAD');
    }
    my ($ext) = $file =~ /\.(\w+)$/;
    my $type = $MIME{lc($ext // '')} // 'application/octet-stream';
    open my $fh, '<:raw', $file or return respond($c, 403, 'Forbidden', 'text/plain', "403\n");
    local $/; my $body = <$fh>; close $fh;
    respond($c, 200, 'OK', $type, $body, $method eq 'HEAD');
}
