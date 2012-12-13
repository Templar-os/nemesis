package Nemesis::ModuleLoader;
use Carp qw( croak );
use Storable qw(dclone freeze thaw);
use TryCatch;

#external modules
my $base = { 'path'         => 'Plugin',
			 'pwd'          => './',
			 'main_modules' => 'Nemesis'
};
our $Init;

sub new
{
	my $class = shift;
	my $self = { 'Base' => $base };
	%{$package} = @_;
	croak 'No init' if !exists( $package->{'Init'} );
	$Init = $package->{'Init'};
	$self->{'Base'}->{'pwd'} = $Init->getEnv()->{'ProgramPath'} . "/";
	return bless $self, $class;
}

sub execute
{
	my $self    = shift;
	my $module  = shift @_;
	my $command = shift @_;
	my @ARGS=@_;

	# my $object  = "$self->{'Base'}->{'path'}::$module";
	#eval( "$self->{'Base'}->{'path'}::$module"->$command(@_) );
	try
	{
		$self->{'modules'}->{$module}->$command(@ARGS);
		$Init->getSession()->execute_save( $module, $command, @ARGS )
			if $module ne "session";
	}
	catch($error) {
		$Init->getIO->print_error("Something went wrong with $command: $error");
	};
}

sub execute_on_all
{
	my $self    = shift;
	my $met     = shift @_;
	my @command = @_;
	foreach my $module ( sort( keys %{ $self->{'modules'} } ) )
	{
		try
		{
			$self->{'modules'}->{$module}->$met(@command);
		}
		catch($error) {
			$Init->getIO->print_error(
				"Something went wrong calling the method '$met' on '$module': $error (Maybe your clear sub is missing?)"
			);
		};
	}
}

sub export_public_methods()
{
	my $self = shift;
	my @OUT;
	my @PUBLIC_FUNC;
	foreach my $module ( sort( keys %{ $self->{'modules'} } ) )
	{
		@PUBLIC_FUNC = ();
		try
		{
			@PUBLIC_FUNC =
				eval { $self->{'modules'}->{$module}->export_public_methods() };
			foreach my $method (@PUBLIC_FUNC)
			{
				$method = $module . "." . $method;
			}
			push( @OUT, @PUBLIC_FUNC );
		}
		catch($error) {
			$Init->getIO()->print_error(
						  "Error $error raised when populating public methods");
		};
	}
	return @OUT;
}

sub listmodules
{
	my $self = shift;
	my $IO   = $Init->getIO();
	$IO->print_title("List of modules");
	foreach my $module ( sort( keys %{ $self->{'modules'} } ) )
	{
		$IO->print_info("$module");
		$self->{'modules'}->{$module}->info()
			; #so i can call also configure() and another function to display avaible settings!
	}
}

sub loadmodule()
{
	my $self        = shift;
	my $module      = $_[0];
	my $IO          = $Init->getIO();
	my $plugin_path = $self->{'Base'}->{'pwd'} . $self->{'Base'}->{'path'};
	my $modules_path =
		$self->{'Base'}->{'pwd'} . $self->{'Base'}->{'main_modules'};
	my $base;
	if ( -e $plugin_path . "/" . $module . ".pm" )
	{
		$base = $self->{'Base'}->{'path'};
	} elsif ( -e $modules_path . "/" . $module . ".pm" )
	{
		$base = $self->{'Base'}->{'main_modules'};
	} else
	{
		return ();
	}

	#$IO->debug("Module $module found in $base");
	my $object = "$base" . "::" . "$module";
	try
	{
		my $o     = dclone( \$object );
		my $realO = $$o;
		$object = $realO->new( Init => $Init );
	}
	catch($error) {
		$Init->getIO()
			->print_error("Something went wrong loading $object: $error");
			return ();
		} $object = eval
	{
		my $o     = dclone( \$object );
		my $realO = $$o;
		return $realO->new( Init => $Init );
	};
	$Init->getIO()->debug("Module $module correctly loaded");
	return $object;
}

sub loadmodules
{
	my $self = shift;
	my @modules;
	my $IO   = $Init->getIO();
	my $path = $self->{'Base'}->{'pwd'} . $self->{'Base'}->{'path'};
	local *DIR;
	if ( !opendir( DIR, "$path" ) )
	{
		$IO->print_error(
					   "[LOADMODULES] - (*) No such file or directory ($path)");
		croak "No such file or directory ($path)";
	}
	my @files = grep( !/^\.\.?$/, readdir(DIR) );
	closedir(DIR);
	my $modules;
	my $mods = 0;
	foreach my $f (@files)
	{
		my $base = $path . "/" . $f;
		my ($name) = $f =~ m/([^\.]+)\.pm/;
		try
		{
			my $result = do($base);
			$self->{'modules'}->{$name} = $self->loadmodule($name);
			$mods++;
		}
		catch($error) {
			$IO->print_error($error);
				delete $INC{ $path . "/" . $name };
				next;
		};
	}
	$IO->print_info("> $mods modules available. Double tab to see them\n");

	# delete $self->{'modules'};
	return 1;
}
1;
