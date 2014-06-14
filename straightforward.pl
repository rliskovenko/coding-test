#!/usr/bin/perl -ls
package CodingTest;

__PACKAGE__->run( @ARGV )
	unless caller();

use common::sense;
use feature qw/say/;

use Carp;
use Data::Section -setup;

my ( %conf, %stats, $FH );

sub show_help {
	print <<'EOH';
Usage:
	$0 [options]
Options:
  -file=filename   -- path to access_log
  -top10           -- show top ten URLs
  -retpctok        -- show percent of successfull requests
  -retpctneg       -- show percent of unsuccessfull requests
  -top10neg        -- show top ten unsuccessfull URLs
  -top10ip         -- show top ten IPs
  -perminute       -- show per-minute stats
  -top10ipdetails  -- show top 10 IPs with top 5 requests each
  -all             -- true for all trigger options
  -h, -help, --help
		   -- show short help
  -selftest, --selftest
	           -- Run embedded self-tests
EOH
	exit;
}

sub get_topN {
	my ( $ref, $n ) = @_;
	croak "get_top10: wrong param"
		unless ref($ref) eq 'HASH'
		&& length( do { no warnings 'numeric'; $n & "" } )
		&& $n >= 1;
	return ( sort {
				$ref->{$b} <=> $ref->{$a}
			} keys %{ $ref } )[0 .. $n-1];
}

sub self_test {
	require 'Test/More.pm';
	Test::More->import( 'no_plan' );
	foreach my $data_ok_section ( sort grep { /^OK_/ } __PACKAGE__->section_data_names() ) {
		my $data_ok = __PACKAGE__->section_data( $data_ok_section );
		my $res_section = $data_ok_section;
		$res_section =~ s/OK/OKRES/;
		my $data_res = __PACKAGE__->section_data( $res_section );
		my $test;
		parse_oneline( $$data_ok, {}, {});
		my $test_res = eval $$data_res;
		is_deeply( $test, $test_res, $data_ok_section );
	}
	exit;
}

sub parse_byline {
	my ($fh, $conf, $stats) = @_;

	while (<$fh>) {
		parse_oneline( $_, $conf, $stats);
	}
}

sub parse_oneline {
	my ($line, $conf, $stats) = @_;

	$line =~ $conf->{line_re};
	my %m = %+;
	my %ret;
	next
		unless keys %m;
	$stats->{top10}{ $m{url} }++
		if $conf->{top10};
	$stats->{req_all}++
		if $conf->{retpctok}
			|| $conf->{retpctneg};
	$stats->{req_ok}++
		if $conf->{retpctok}
			&& $m{retcode} =~ $conf->{retcode_ok};
	$stats->{req_neg}++
		if $conf->{retpctneg}
			&& $m{retcode} !~ $conf->{retcode_ok};
	$stats->{top10neg}{ $m{url} }++
		if $conf->{top10neg}
			&& $m{retcode} !~ $conf->{retcode_ok};
	$stats->{top10ip}{ $m{ip} }++
		if $conf->{top10ip}
			|| $conf->{top10ipdetails};
	$stats->{top10ipdetails}{ $m{ip} }{$m{url} }++
		if $conf->{top10ipdetails};
}

### MAIN
sub run {
	{
		no warnings;
		# Show help if requested
		show_help()
			if $main::h || $main::help || $main::{-help};
		self_test
			if $main::selftest || $main::{-selftest};

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
			if $main::all
			|| ! grep { $conf{$_} } keys %conf;
	}
	# Open file
	open ($FH, '<', $main::file )
		|| croak "Unable to open input: $main::file ($!)";

	# Pre-compile regular expression
	$conf{line_re} = qr/
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
	$conf{retcode_ok} = qr/^[23]/isx;

	parse_byline( $FH, \%conf, \%stats);

	close $FH
		|| carp "Error closing file: $!";

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
}

__DATA__
__[ OK_1 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 400 216
__[ OKRES_1 ]__
1
__[ OK_2 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET /test/url? HTTP/1.1" 200 216
__[ OKRES_2 ]__
2
__[ NEG_1 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 200 216
__[NEG_2 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 300 216
