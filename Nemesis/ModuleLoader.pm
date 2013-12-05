package Nemesis::ModuleLoader;
{
    # no warnings 'redefine';
    # use Try::Tiny;
    # use TryCatch;
    use Module::Loaded;
    use LWP::Simple;
    use Regexp::Common qw /URI/;
    use File::Find;

    #external modules
    my @MODULES_PATH = ( 'Plugin', 'Resources', 'MiddleWare' );
    our @SystemCommands = ( "reload", "exit" );    #Exported by defaultxh

    ###### The::Net hack
    push @INC => sub {

        #    require LWP::Simple;
        #  require Resources::Network::HTTPInterface;
        require IO::File;
        require Fcntl;

        my $url = pop;

        return unless $url =~ m{^\w+://};

        # my $document = LWP::Simple::get($url)
        #[]       or die "Failed to fetch $url: $!\n";
        my $reponse = Resources::Network::HTTPInterface->new->get($url);
        my $document;
        $document = $response->{content} if length $response->{content};

        my $fh = IO::File->new_tmpfile
            or die "Failed to create temp file: $!\n";
        $fh->print($document) or die "Failed to print: $!\n";
        $fh->seek( 0, Fcntl::SEEK_SET() ) or die "Failed to seek: $!\n";

        $fh;
    };

    our $Init;

    sub new {
        my $class = shift;
        my $self = { 'Base' => $base };
        %{$package} = @_;
        $Init = $package->{'Init'};
        $self->{'Base'}->{'pwd'} = $Init->getEnv()->{'ProgramPath'} . "/";
        return bless( $self, $class );
    }

    sub execute {
        my $self    = shift;
        my $module  = shift @_;
        my $command = shift @_;
        my $return;
        my @ARGS          = @_;
        my $currentModule = $self->{'modules'}->{$module};
        eval {
            if ( eval { $currentModule->can($command); } ) {
                if ( $return = $currentModule->$command(@ARGS) ) {
                    $Init->getSession()
                        ->execute_save( $module, $command, @ARGS )
                        if $module ne "session";
                }
            }
            else {
                $Init->getIO->debug("$module doesn't provide $command");
            }
        };
        if ($@) {
            $Init->getIO->print_error(
                "Something went wrong calling the method '$command' on '$module': $@"
            );
        }
        return $return;
    }

    sub execute_on_all {
        my $self    = shift;
        my $met     = shift @_;
        my @command = @_;
        foreach my $module ( sort( keys %{ $self->{'modules'} } ) ) {
            $Init->io->debug( "Executing $met on $module", __PACKAGE__ );
            $self->execute( $module, $met, @command );
        }
    }

    sub export_public_methods() {
        my $self = shift;
        my @OUT;
        my @PUBLIC_FUNC;
        foreach my $module ( sort( keys %{ $self->{'modules'} } ) ) {
            @PUBLIC_FUNC = ();
            eval {
                @PUBLIC_FUNC = eval {
                    $self->{'modules'}->{$module}->export_public_methods();
                };
                foreach my $method (@PUBLIC_FUNC) {
                    $method = $module . "." . $method;

                    # $Init->io->debug($method ." is avaible");
                }
                push( @OUT, @PUBLIC_FUNC );
            };
            if ($@) {
                $Init->getIO()
                    ->print_error(
                    "Error $@ raised when populating public methods");
            }
        }
        return @OUT, @SystemCommands;
    }

    sub listmodules {
        my $self = shift;
        my $IO   = $Init->getIO();
        $IO->print_title("List of modules");
        foreach my $module ( sort( keys %{ $self->{'modules'} } ) ) {
            $IO->print_info("$module");
            $self->{'modules'}->{$module}->info();
        }
    }

    sub _findLibName {
        my $self  = shift;
        my $URL   = $_[0];
        my $Fetch = get($URL);
        while ( $Fetch =~ /package\s+(.*?)\;/i ) {
            return $1;
        }

    }

    sub resolvObj() {
        my $self   = shift;
        my $module = shift;
        my $object;
        if ( $module =~ /$RE{URI}{HTTP}/ ) {
            require $module;
            $object = $self->_findLibName($module);

        }
        elsif ( $module =~ /\:\:/ ) {
            $object = $module;
        }
        elsif ( my $Type = $self->_findLib($module) ) {
            if ( $Type =~ /\// ) { $Type =~ s/\//\:\:/g; }
            $object = $Type . "::" . $module;
        }
        else {
            $object = "Nemesis::" . $module;

        }
        if ( $object =~ /par\-/ ) {
            $object2 = $object;
            $object2 =~ s/.*?inc\:lib\://g;
            return $object2;
        }
        chomp($object);
        return $object;
    }

    sub loadmodule() {
        my $self   = shift;
        my $module = $_[0];
        if ( $_[1] ) {
            my %args = %{ $_[1] };
        }
        my $IO     = $Init->getIO();
        my $object = $self->resolvObj($module);

        if ( !is_loaded($object) ) {
            $Init->getIO()->debug( "loading plugin $object ", __PACKAGE__ );
            eval("use $object");
            if ($@) {
                $Init->getIO()
                    ->print_error("Something went wrong loading $object: $@");
                return ();
            }
        }
        if (%args) {
            eval { $object = $object->new( Init => $Init, %args ); };
        }
        else {
            eval { $object = $object->new( Init => $Init ); };
        }
        if ($@) {
            $Init->getIO()
                ->print_error("Something went wrong loading $object: $@");
            return ();
        }

        $Init->getIO->debug( "$object provides: "
                . join( " ", $object->export_public_methods ) )
            if eval { $object->can("export_public_methods") };
        $Init->io->debug("Preparing $object") and $object->prepare()
            if ( eval { $object->can("prepare") } );
        return $object;
    }

    sub getInstance() {
        my $self     = shift;
        my $Instance = $_[0]
            ; #Only plugins get istances. single name, no namespace on plugins.
        return $self->{'modules'}->{$Instance}
            if ( exists( $self->{'modules'}->{$Instance} ) );
    }

    sub canModule() {
        my $self = shift;
        my $Can  = shift;
        return @{ $self->{'can'}->{$Can} }
            if ( exists( $self->{'can'}->{$Can} ) );
        $self->{'can'}->{$Can} = [];
        foreach my $module ( sort( keys %{ $self->{'modules'} } ) ) {
            my $Mod = $self->{'modules'}->{$module};
            if ( eval { $Mod->can($Can); } ) {
                push( @{ $self->{'can'}->{$Can} }, $module );

                #$Init->getIO->debug("$module cached");
            }
        }

# $Init->getIO->debug("Who can $Can? ".join(" ",@{$self->{'can'}->{$Can}})." \n");

        return @{ $self->{'can'}->{$Can} };
    }

    sub _findLib() {

        my $self    = shift;
        my $LibName = $_[0];
        #

        foreach my $Library ( $self->getLoadedLib ) {
            my $Path  = $Init->getEnv()->getPathBin;
            my $Match = $Library;
            $Match =~ s/$Path\/?//g;
            #
            #$Init->getIO()->debug( "Lib $Match for $LibName", __PACKAGE__ );
            my @I = @INC;
            my $c = 0;
            foreach my $a (@I) {
                delete $I[$c] if ( $I[$c] eq "." );
                $c++;
            }

            foreach my $INCLib (@I) {
                $Match =~ s/$INCLib//g
                    if defined($INCLib);
            }

#   $Init->getIO->debug("this is my match $Match INC is ".join(" ",@I),__PACKAGE__);
            if ( $Match =~ /\/?(.*)\/$LibName/i ) {

#
#   $Init->getIO->debug(" findLib matched $1 for $Match ($LibName)",__PACKAGE__);
                return $1;
            }
        }
    }

    sub _findLibsByCategory() {

        #Not used by now, maybe from the packer.
        my $self    = shift;
        my $LibName = $_[0];
        my @Result;

        foreach my $Library ( $self->getLoadedLib ) {
            my $Path  = $Init->getEnv()->getPathBin;
            my $Match = $Library;
            $Match =~ s/$Path\/?//g;

            if ( $Match =~ /$LibName/i ) {
                push( @Result, $Library );
            }
        }

        # foreach my $INCLib (@INC) {
        #     if ( -d $INCLib . "/" . $LibName ) {
        #         local *DIR;
        #         if ( opendir( DIR, $INCLib . "/" . $LibName ) ) {
        #             @Result =
        #                 map { $_ = $LibName . "/" . $_; }
        #                 grep( !/^\.\.?$/, readdir(DIR) );
        #             close DIR;
        #             last;

        #         }

      #     }
      #     elsif ( -d $Init->getEnv()->getPathBin . "/" . $LibName ) {
      #         local *DIR;
      #         if (opendir( DIR, $Init->getEnv()->getPathBin . "/" . $LibName
      #             )
      #             )
      #         {
      #             @Result =
      #                 map { $_ = $LibName . "/" . $_; }
      #                 grep( !/^\.\.?$/, readdir(DIR) );
      #             close DIR;
      #             last;

        #         }
        #     }
        # }
        # $Init->getIO()->debug( "FOUND " . join( " ", @Result ) );

        return @Result;

    }

    sub getLoadedLib() {
        my $self = shift;
        return @{ $self->{'LibraryList'} };
    }

    sub getLibs() {
        my $self = shift;
        my $IO   = $Init->getIO();
        my $Path = $Init->getEnv()->getPathBin;
        my @Libs;
        foreach my $Library (@MODULES_PATH) {
            local *DIR;
            if ( !opendir( DIR, $Path . "/" . $Library ) ) {
                ##Se non riesco a vedere in locale, forse sono nell'INC?
                $IO->print_alert( "No "
                        . $Path . "/"
                        . $Library
                        . " detected to find modules" );
                foreach my $INCLib (@INC) {
                    if ( -d $INCLib . "/" . $Library ) {

                        #Oh, eccoli!
                        # opendir( DIR, $INCLib . "/" . $Library );
                        # push( @Libs,
                        #     map { $_ = $INCLib . "/" . $Library . "/" . $_ }
                        #     grep( !/^\.\.?$/, readdir(DIR) ) );
                        # closedir(DIR);

                        push( @Libs,
                            $self->traverseDir( $INCLib . "/" . $Library ) );

                    }
                }
            }
            else {
                # push(
                #     @Libs,
                #     map {
                #         $_ =
                #               $self->{'Base'}->{'pwd'}
                #             . $Library . "/"
                #             . $_
                #         }
                #         grep( !/^\.\.?$/, readdir(DIR) )
                # );
                push( @Libs, $self->traverseDir( $Path . "/" . $Library ) );

            }

        }
        $self->{'LibraryList'} = \@Libs;
        return @Libs;
    }

    sub traverseDir() {
        my $self = shift;
        my $dir  = shift;
        my @Res;

        find(
            sub {
                push( @Res, $File::Find::name ) if -f;
            },
            $dir
        );

        return @Res;

    }

    sub unload() {
        my $self  = shift;
        my $Class = shift;
        my $Pm    = shift;

        # Flush inheritance caches
        @{ $Class . '::ISA' } = ();

        my $symtab = $Class . '::';

        # Delete all symbols except other namespaces
        for my $symbol ( keys %$symtab ) {
            next if $symbol =~ /\A[^:]+::\z/;
            delete $symtab->{$symbol};

        }
        if ( eval { $Class->can("meta") } ) {
            $Class->DEMOLISH();
        }
        my $AlreadyLoaded = $Pm;
        my $Path          = $Init->env->getPathBin;
        $AlreadyLoaded =~ s/$Path\///;
        $Init->io->debug(" Unloading $Class in $AlreadyLoaded ");
        if ( exists( $INC{$AlreadyLoaded} ) ) {

            #Doing this throws error on moose immutables objects
            delete $INC{$AlreadyLoaded};
        }
    }

    sub loadmodules {
        my $self            = shift;
        my @selectedModules = ();
        my $IO              = $Init->getIO();
        @selectedModules = @_ if @_ > 0;
        my @modules;
        my @Libs = $self->getLibs;
        my $modules;
        my $mods         = 0;
        my $res          = 0;
        my $unknown_data = 0;
        my $Path         = $Init->getEnv()->getPathBin;
        @{ $self->{'LibraryList'} } = @Libs;

        foreach my $Library (@Libs) {
            my ($name) = $Library =~ m/([^\.|^\/]+)\.pm/;
            next if !$name;
            next
                if @selectedModules > 0
                and !&_match( \@selectedModules, $name ); ## XXX: Note, should change behaviour here, need an array of libs to load, not to avoid them thru the cycle
            my $Class = $self->resolvObj($name);
            $self->unload( $Class, $Library );
            $Init->getIO()
                ->debug( "detected Plugin/Resource $name in $Library",
                __PACKAGE__ );
            eval {
                if ( exists( $self->{'modules'}->{$name} ) ) {
                    delete $self->{'modules'}->{$name};
                }
                if ( $self->isModule($Library) ) {

                    $Init->getIO()
                        ->debug( $Library . " is a module!", __PACKAGE__ );

                    $self->{'modules'}->{$name} = $self->loadmodule($name);
                    if ( exists( $self->{'modules'}->{$name} )
                        and eval { $self->{'modules'}->{$name}->can("new") } )
                    {
                        $mods++;
                        $Init->getIO->print_info(
                            "Module $name ($Library) correctly loaded.");

                    }

                }
                elsif ( $self->isResource($Library) ) {
                    $res++;

#$Init->getIO()->debug("$Library ($name) is a Nemesis Resource",__PACKAGE__ );
                    $Init->getIO->print_info(
                        "Resource $name ($Library) detected");
                }
                else {
                    $unknown_data++;
                    $Init->getIO()
                        ->debug( "$Library it's nothing to me", __PACKAGE__ );
                }

            };
            if ($@) {
                $IO->print_error($@);
                delete $self->{'modules'}->{$name};

                # return 0;
            }
        }
        $IO->print_info(
            " $mods modules\n\t$res resources\n\t$unknown_data unknown data are available.\n\tDouble tab to see them"
        );

        #delete $self->{'modules'};
        return 1;
    }

    sub isModule() {
        my $self   = shift;
        my $module = $_[0];
        open MODULE, "<" . $module
            or $Init->getIO()->print_alert("$module can't be opened");
        my @MOD = <MODULE>;
        close MODULE;
        my $f = 0;
        foreach my $rigo (@MOD) {

            if ( $rigo
                =~ /(?<![#|#.*|.?#])nemesis\s+module|(?<![#|#.*|.?#])Nemesis\:\:BaseModule/
                )
            {

                return 1;
            }
        }
        return 0;
    }

    sub isResource() {
        my $self   = shift;
        my $module = $_[0];
        open MODULE, "<" . $module
            or $Init->getIO()->print_alert("$module can't be opened");
        my @MOD = <MODULE>;
        close MODULE;
        my $f = 0;

        foreach my $rigo (@MOD) {
            if ( $rigo
                =~ /(?<![#|#.*|.?#])nemesis\s+(resource|mojo)|(?<![#|#.*|.?#])Nemesis\:\:BaseRes/
                )
            {
                return 1;

            }
        }
        return 0;
    }

    ############# array match ##############
    sub _match() {
        #        my $self  = shift;
        my $array = shift;
        my $value = shift;
        my %hash = map { $_ => 1 } @$array;
        $hash{$value} ? return 1 : return 0;
    }

    ############# ALIASES #############
    sub instance() {
        my $self = shift;
        $self->getInstance( $_[0] );
    }

    sub atom() {
        my $self = shift;
        $self->loadmodule(@_);
    }

    sub load() {
        my $self = shift;
        $self->loadmodule(@_);
    }

}
1;
