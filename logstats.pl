#!/usr/bin/perl -ls
package CodingTest;

__PACKAGE__->run( @ARGV )
	unless caller();

use common::sense;
use feature qw/say/;

use Carp;
use Data::Dumper;
use DateTime;
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
  -perminute=YYYYMMDDHHmm-YYYYMMDDHHmm
                   -- per minute request count for given timeframe
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
	$main::all = 1;
	my %conf = get_conf();
	foreach my $data_ok_section ( sort grep { /^OK_/ } __PACKAGE__->section_data_names() ) {
		my $data_ok = __PACKAGE__->section_data( $data_ok_section );
		my $res_section = $data_ok_section;
		$res_section =~ s/OK/OKRES/;
		my $data_res = __PACKAGE__->section_data( $res_section );
		my %test;
		parse_oneline( $_, \%conf, \%test)
			foreach split("\n", $$data_ok);
		my %test_res = %{ eval $$data_res };
		is_deeply( \%test, \%test_res, $data_ok_section );
	}

	foreach my $data_ok_section ( sort grep { /^NEG_/ } __PACKAGE__->section_data_names() ) {
		my $data_ok = __PACKAGE__->section_data( $data_ok_section );
		my $res_section = $data_ok_section;
		$res_section =~ s/NEG/NEGRES/;
		my $data_res = __PACKAGE__->section_data( $res_section );
		my %test;
		parse_oneline( $_, \%conf, \%test)
			foreach split("\n", $$data_ok);
		my %test_res = %{ eval $$data_res };
		isnt( \%test, \%test_res, $data_ok_section );
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
	return
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
	if ( $conf->{perminute}
		&& $conf->{start_time} && $conf->{stop_time} ) {
		$m{dt} =~ m/
			(?<day>\d{2})
			\/
			(?<month>[^\d]+)
			\/
			(?<year>\d{4})
			:
			(?<hour>\d{2})
			:
			(?<minute>\d{2})
		/isx;
		my %cur_time;
		@cur_time{qw/year day month hour minute/} =
			@+{qw/year day month hour minute/};
		#Take care of month abbrevation
		$cur_time{month} = $conf->{month_abbr}{ lc($cur_time{month}) };
		my $cur_time_dt = DateTime->new( %cur_time );
		$stats->{perminute}{ $cur_time_dt->datetime() }++
			if $cur_time_dt >= $conf->{start_time}
				&& $cur_time_dt <= $conf->{stop_time};
	}
}

sub get_conf {
	# Set configuration with defaults
	my %conf = (
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
	if ($main::perminute) {
		my ($t_start, $t_stop) = split('-', $main::perminute);
		$conf{perminute} = 1;
		my $timesplitter = qr/
			(?<year>\d{4})
			(?<month>\d{2})
			(?<day>\d{2})
			(?<hour>\d{2})
			(?<minute>\d{2})
		/isx;
		my %m;
		$t_start =~ $timesplitter;
		@m{qw/year month day hour minute/} =
			@+{qw/year month day hour minute/};
		$conf{start_time} = DateTime->new( %m )
			if keys %m;
		$t_stop =~ $timesplitter;
		@m{qw/year month day hour minute/} =
			@+{qw/year month day hour minute/};
		$conf{stop_time} = DateTime->new( %+ )
			if keys %m;
	}
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
	%{ $conf{month_abbr} } = qw/ jan 1 feb 2 mar 3 apr 4 may 5 jun 6 jul 7
aug 8 sep 9 oct 10 nov 11 dec 12/;
	return wantarray ? %conf : \%conf;
}

### MAIN
sub run {
	%conf = get_conf();

	{
		no warnings;
		# Show help if requested
		show_help()
			if $main::h || $main::help || $main::{-help};
		self_test
			if $main::selftest || $main::{-selftest};
	}
	# Open file
	open ($FH, '<', $main::file )
		|| croak "Unable to open input: $main::file ($!)";

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

	if ($conf{perminute}) {
		say "######################";
		say "Per-minute hit stats: ";
		say "######################";
		foreach my $dt ( sort keys %{ $stats{perminute} }) {
			say $stats{perminute}{$dt}, "\t", $dt;
		}
	}


	exit();
}

__DATA__

__[ OK_1 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 400 216
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 300 216
__[ OKRES_1 ]__
{
	top10 => {
		'/' => 2
	},
	top10ipdetails => {
		'1.1.1.1' => {
			'/' => 2
		}
	},
	top10ip => {
		'1.1.1.1' => 2
	},
	req_ok => 1,
	req_neg => 1,
	req_all => 2,
	top10neg => {
			'/' => 1
	}
}

__[ OK_2 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET /test/url? HTTP/1.1" 200 216
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET /test HTTP/1.1" 300 216
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET /test/url? HTTP/1.1" 200 216
1.1.1.2 - - [21/Mar/2011:06:02:32 +0000] "GET /test/url? HTTP/1.1" 400 216
__[ OKRES_2 ]__
{
	top10 => {
		'/test/url?' => 3,
		'/test' => 1
	},
	top10ipdetails => {
		'1.1.1.1' => {
			'/test/url?' => 2,
			'/test' => 1
		},
		'1.1.1.2' => {
			'/test/url?' => 1
		}
	},
	top10ip => {
		'1.1.1.1' => 3,
		'1.1.1.2' => 1
	},
	req_neg => 1,
	req_ok => 3,
	req_all => 4,
	top10neg => {
		'/test/url?' => 1
	}
}
__[ OK_3 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 400 216
__[ OKRES_3 ]__
{
	top10 => {
		'/' => 1
	},
	top10ipdetails => {
		'1.1.1.1' => {
			'/' => 1
		}
	},
	top10ip => {
		'1.1.1.1' => 1
	},
	req_neg => 1,
	req_all => 1,
	top10neg => {
			'/' => 1
	}
}
__[ OK_4 ]__
1.1.1.1 - - [21/Mar/2011:06:02:32 +0000] "GET / HTTP/1.1" 300 216
__[ OKRES_4 ]__
{
	top10 => {
		'/' => 1
	},
	top10ipdetails => {
		'1.1.1.1' => {
			'/' => 1
		}
	},
	top10ip => {
		'1.1.1.1' => 1
	},
	req_ok => 1,
	req_all => 1,
}
