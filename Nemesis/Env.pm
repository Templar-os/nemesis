package Nemesis::Env;
use warnings;
use FindBin '$Bin';
our $Init;

sub new
{
	my $package = shift;
	bless( {}, $package );
	%{$package} = @_;
	$package->scan_env();
	if ( !-d $package->{'workspace'} )
	{
		mkdir( $package->{'workspace'} );
	}
	if ( !-d $package->{'workspace'} . "/tmp" )
	{
		mkdir( $package->{'workspace'} . "/tmp" );
	}
	$Init = $package->{'Init'};
	$package->{"ProgramPath"} = $Bin;
	return $package;
}

sub getPathBin(){
	my $self=shift;
	return $self->{"ProgramPath"};
}

sub print_env()
{
	my $self = shift;
	foreach my $key ( keys %ENV )
	{
		$Init->getIO->print_info( $key . " : " . $ENV{$key} );
	}
}

sub scan_env()
{
	my $self = shift;
	my @path = split( /\:/, $ENV{'PATH'} );
	@{ $self->{'path'} } = @path;
	$self->{'workspace'} = $self->select_info("HOME") . "/.nemesis_data";

	#print %ENV;
}

sub select_info()
{
	my $self = shift;
	my $var  = $_[0];
	foreach my $key ( keys %ENV )
	{
		if ( $key eq $var )
		{
			return $ENV{$var};
		}
	}
}

sub ipv4_forward
{
	my $self = shift;
	if ( $_[0] eq "on" )
	{
		open FILE, ">/proc/sys/net/ipv4/ip_forward";
		print FILE 1;
		close FILE;
	} elsif ( $_[0] eq "off" )
	{
		open FILE, ">/proc/sys/net/ipv4/ip_forward";
		print FILE 0;
		close FILE;
	}
	open FILE, "</proc/sys/net/ipv4/ip_forward";
	my $res = <FILE>;
	return $res;
}

sub check_root()
{
	if ( $> == 0 )
	{
		return 1;
	}
	return 0;
}

sub path()
{
	my $self = shift;
	return
		@{ $self->{'path'}
		};    #acquisisce l'array precedentemente messo nella chiave "devices"
}

sub whereis
{
	my $self       = shift;
	my $dependency = $_[0];
	if ( exists( $self->{'ENV'}->{$dependency} ) )
	{
		return $self->{'ENV'}->{$dependency};
	} else
	{
		foreach my $path ( @{ $self->{'path'} } )
		{
			@FILES = <$path/*>;
			foreach my $p (@FILES)
			{
				return $p if $p eq "$path\/$dependency";
			}
		}
		foreach my $path ( @{ $self->{'path'} } )
		{
			@FILES = <$path/*>;
			foreach my $p (@FILES)
			{
				return $p if $p =~ /$dependency/i;
			}
		}
	}
	return;
}

sub wherepath
{
	my $self       = shift;
	my $dependency = $_[0];
	if ( exists( $self->{'ENV'}->{$dependency} ) )
	{
		return $self->{'ENV'}->{$dependency};
	} else
	{
		foreach my $path ( @{ $self->{'path'} } )
		{
			@FILES = <$path/*>;
			foreach my $p (@FILES)
			{
				return $path if $p eq "$path\/$dependency";
			}
		}
		foreach my $path ( @{ $self->{'path'} } )
		{
			@FILES = <$path/*>;
			foreach my $p (@FILES)
			{
				return $parh if $p =~ /$dependency/i;
			}
		}
	}
	return;
}

sub path_for()
{
	my $self = shift;
	my ( $i, $path ) = @_;
	$self->{'ENV'}->{$i} = $path;
}

sub workspace()
{
	my $self = shift;
	return $self->{'workspace'};
}

sub tmp_dir()
{
	my $self = shift;
	return $self->{'workspace'} . "/tmp";
}

sub time()
{
	my $self     = shift;
	my @months   = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ( $second,     $minute,    $hour,
		 $dayOfMonth, $month,     $yearOffset,
		 $dayOfWeek,  $dayOfYear, $daylightSavings
	) = localtime(time);
	if ( length($hour) == 1 )   { $hour   = "0" . $hour; }
	if ( length($minute) == 1 ) { $minute = "0" . $minute; }
	my $year = 1900 + $yearOffset;
	return
		  $dayOfMonth . "."
		. $months[$month] . "."
		. $year . "_"
		. $hour . "-"
		. $minute;
}

sub time_seconds()
{
	my $self     = shift;
	my @months   = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ( $second,     $minute,    $hour,
		 $dayOfMonth, $month,     $yearOffset,
		 $dayOfWeek,  $dayOfYear, $daylightSavings
	) = localtime(CORE::time);
	my $year = 1900 + $yearOffset;
	if ( length($hour) == 1 )   { $hour   = "0" . $hour; }
	if ( length($minute) == 1 ) { $minute = "0" . $minute; }
	if ( length($second) == 1 ) { $second = "0" . $second; }
	return "$hour:$minute:$second";
}

sub time_pid{
		my $self     = shift;
	my @months   = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ( $second,     $minute,    $hour,
		 $dayOfMonth, $month,     $yearOffset,
		 $dayOfWeek,  $dayOfYear, $daylightSavings
	) = localtime(CORE::time);
	my $year = 1900 + $yearOffset;
	if ( length($hour) == 1 )   { $hour   = "0" . $hour; }
	if ( length($minute) == 1 ) { $minute = "0" . $minute; }
	return "$hour:$minute";
	
	
}
1;
__END__
