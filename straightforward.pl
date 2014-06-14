#!/usr/bin/perl -ls

use common::sense;
use feature qw/say/;

use Carp;
use Data::Dumper;
my %conf = ();
my %stats = ();
my $FH;

sub show_help {
	print <<'EOH';
Usage:
	$0 [options]
Options:
  -file=filename
  -top10
  -retpctok
  -retpctneg
  -top10neg
  -top10ip
  -perminute
  -top10ipdetails
  -all
  -h, -help, --help
EOH
	exit;
}

sub get_topN {
	my ( $ref, $n ) = @_;
	croak "get_top10: wrong param"
		unless ref($ref) eq 'HASH' 
		and length( do { no warnings 'numeric'; $n & "" } )
		and $n >= 1;
	return ( sort { 
				$ref->{$b} <=> $ref->{$a} 
			} keys %{ $ref } )[0 .. $n-1];
}

{
	no warnings;
	# Show help if requested
	show_help()
		if $main::h || $main::help || $main::{-help};

	# Set configuration with defaults
	%conf = (
		top10 => $main::top10 || 0,
		retpctok => $main::retpctok || 0,
		retpctneg => $main::retpctneg || 0,
		top10neg => $main::top10neg || 0,
		top10ip => $main::top10ip || 0,
		perminute => $main::perminute || 0,
		top10ipdetails => $main::top10ipdetails || 0,
	);
	# -all CLI option sets all flags, no options at all set them too
	%conf = map { $_ => 1 } keys %conf
		if $main::all || ! grep { $conf{$_} } keys %conf;
}
# Open file
open ($FH, '<', $main::file )
	or croak "Unable to open input: $main::file ($!)";

# Pre-compile regular expression
my $line_re = qr/
	^
	(?P<ip>\d+\.\d+\.\d+\.\d+)
	\s+\S+\s+\S+\s+
	\[
	  (?P<dt>\S+)
	  \s+
	  (?P<tz>
	  \S+)
	\]\s+
	\"
	  (?P<method>\S+)
	  \s+
	  (?P<url>.+?)
	  \s+
	  (?P<proto>.+)
	\"
	\s+
	(?P<retcode>\d+)
	\s+
	(?P<size>\d+)
/isx;
my $retcode_ok = qr/^[23]/isx;

# sysread() is unpredictable in performance
while (<$FH>) {
	m/$line_re/isx;
	my %m = %+;
	next 
		unless keys %m;
	$stats{top10}{ $m{url} }++
		if $conf{top10};
	$stats{req_all}++
		if $conf{retpctok} || $conf{retpctneg};
	$stats{req_ok}++
		if $conf{retpctok} && $m{retcode} =~ $retcode_ok;
	$stats{req_neg}++
		if $conf{retpctneg} && $m{retcode} !~ $retcode_ok;
	$stats{top10neg}{ $m{url} }++
		if $conf{top10neg} && $m{retcode} !~ $retcode_ok;
	$stats{top10ip}{ $m{ip} }++
		if $conf{top10ip} or $conf{top10ipdetails};
	$stats{top10ipdetails}{ $m{ip} }{$m{url} }++
		if $conf{top10ipdetails};
}

close $FH
	or carp "Error closing file: $!";

# Output as requested by cli options
if ($conf{top10}) {
	say "##################";
	say "### Top ten URLs: ";
	say "##################";
	say $stats{top10}{ $_ }, "\t", $_
		foreach get_topN( $stats{top10}, 10 ); 
}

if ($conf{retpctok}) {
	say "####################";
	say "### Requests OK, %: ";
	say "####################";
	say $stats{req_ok}/$stats{req_all};
}

if ($conf{retpctneg}) {
	say "########################";
	say "### Requests failed, %: ";
	say "########################";
	say $stats{req_neg}/$stats{req_all};
}

if ($conf{top10neg}) {
	say "#########################";
	say "### Top ten failed URLs: ";
	say "#########################";
	say $stats{top10neg}{ $_ }, "\t", $_
		foreach get_topN( $stats{top10neg}, 10 );
}

if ($conf{top10ip}) {
	say "#################";
	say "### Top ten IPs: ";
	say "#################";
	say $stats{top10ip}{ $_ }, "\t", $_
		foreach get_topN( $stats{top10ip}, 10 );
}

if ($conf{top10ipdetails}) {
	say "####################################";
	say "### Top ten IPs with top five urls: ";
	say "####################################";
	foreach my $ip ( get_topN( $stats{top10ip}, 10 ) ) {
		say "IP: ", $ip;
		say $stats{top10ipdetails}{$ip}{$_}, "\t", $_
			foreach get_topN( $stats{top10ipdetails}{$ip}, 5);
		say;
	}
}

exit();

