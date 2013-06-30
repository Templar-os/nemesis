package MiddleWare::Bundle;

use Class::Accessor "antlers";
#use PAR::Packer ();
#use PAR         ();
use Module::ScanDeps;
use Nemesis::Inject;
use App::Packer::PAR;
our $VERSION          = '0.1a';
our $AUTHOR           = "mudler";
our $MODULE           = "This is an interface to the Packer library";
our $INFO             = "<www.dark-lab.net>";
our @PUBLIC_FUNCTIONS = qw( test export exportCli exportWrap);
has What  => ( is => "rw" ); 
has Where => ( is => "rw" );
has BundlePAR => (is=> "rw");
has PerlOutput => (is=> "rw");
has Modules => (    is      => "rw");

nemesis_module;

sub prepare(){
    my $self=shift;
 #   $self->BundlePAR(1);
  #  $self->PerlOutput(1);
   # $self->Modules([]);
}

sub test(){
    my $self=shift;
    $Init->io->info("Test passed");
}

sub export( ) {
    my $self = shift;
    my $What;
    my $Filename;
    if ( scalar(@_) != 0 ) {
        $What     = shift;
        $Filename = shift;
        $self->What($What);
        $self->Where($Filename);
    }

    if ( !$self->What || !$self->Where ) {
        $Init->io->debug("You have not What and Where");
    }

    $self->Init->getIO()
        ->print_info( "Packing " . $self->What . "in " . $self->Where );
    $self->pack();
    $self->Init->getIO()->print_info("Packing done");

}

sub exportCli() {
    my $self  = shift;
    my $Where = shift;
    if ( defined($Where) ) {
        $self->Where($Where);
    }
    my $path = $Init->env->getPathBin();
    $self->export( $path . "/nemesis", $self->Where );

}

sub exportWrap() {
    my $self  = shift;
    my $Where = shift;
    if ( defined($Where) ) {
        $self->Where($Where);
    }
    my $path = $self->Init->getEnv()->getPathBin();
    $self->export( $path . "/wrapper.pl", $self->Where );
}

sub pack() {
    my $self = shift;
    my ( $What, $FileName ) = ( $self->What, $self->Where );
    my $parpath = $Init->getEnv()->wherepath("par.pl");
    my @LOADED_PLUGINS;
    if(scalar(@{$self->Modules}) == 0){
        $Init->io->info("No modules defined, bundling all");
                @LOADED_PLUGINS = grep /./i, map {
                my ($Name) = $_ =~ m/([^\.|^\/]+)\.pm$/;
                if ($Name) {
                    $_ =
                          $Init->getModuleLoader()->_findLib($Name) . "/"
                        . $Name . ".pm";
                }
                else {
                    $_ = ();
                }
            } $Init->getModuleLoader()->getLoadedLib();
    } else {
        @LOADED_PLUGINS=@{$self->Modules};
    }

               my @OPTS = ($What);


            $Init->getIO->print_info(
                "Those are the library that i'm bundling in the unique file $FileName :"
            );
            foreach my $Modules (@LOADED_PLUGINS) {
                $Init->getIO->print_tabbed( $Modules, 2 );
            }

#my @Deps_Mods=Module::ScanDeps::scan_line($Init->getModuleLoader()->getLoadedLib());

            #  my $files=scan_deps(
            #   files   => [     @Deps_Mods, keys %INC],
            #      recurse => 1,
            #      compile => 1,

            #      );
            #  $Init->io->debug_dumper(\%INC);
            #  $Init->io->debug_dumper( \$files);
            # push(@Deps_Mods,keys %{$files});

            $Init->getIO->print_info(
                "Acquiring Plugin dependencies... please wait");
      

my @IncDeps;
foreach my $k( keys %INC){
    push (@IncDeps,$k) if($k=~/\.pm/);
}


            push( @LOADED_PLUGINS ,@IncDeps);

          #my @CORE_MODULES= $Init->getModuleLoader()->_findLibsByCategory("Nemesis");
          #push(@LOADED_PLUGINS,@CORE_MODULES);
            $Init->getIO->print_info("Filled with deps :");
            my @Additional_files;
            my $c = 0;
            foreach my $Modules (@LOADED_PLUGINS) {
                if ( $Modules !~ /\.txt|\.pm|\.pl/ or $Modules=~/DynaLoader|XS/i) {

                    # $Init->io->debug("Tooo bad for you $Modules");
                    push( @Additional_files, $Modules );
                    delete $LOADED_PLUGINS[$c];
                }else {
                                  $Init->getIO->print_tabbed( $Modules, 2 );
  
                }

                $c++;
            }

            my %opt;

            #For Libpath add
            my @LIBPATH;
            push( @LIBPATH, $Init->getEnv->getPathBin );
            $opt{P} = $self->PerlOutput;    #Output perl
              $opt{c}=1; #compiles-> MUST BE ENABLED ONLY WHEN LIBRARY ARE INSTALLED IN O.S.
              #OTHERWISE NOTHING OF WHAT IS "USING" a PLUGIN WILL BE BUNDLED (e.g. MoooseX::Declare)
            $opt{vvv} = 1;
            $opt{o} = $FileName;

         #   $opt{x} =1; #with this it still works!
            $opt{B} = $self->BundlePAR;
            #$opt{a} = \@Additional_files;
            $opt{M} = \@LOADED_PLUGINS;
            $opt{l} = \@LIBPATH;
            $Init->getSession->safedir(
                $parpath,
                sub {
                    App::Packer::PAR->new(
                        frontend  => 'Module::ScanDeps', 
                        backend   => 'PAR::Packer',
                        frontopts => \%opt,
                        backopts  => \%opt,
                        args      => \@OPTS
                    )->go;

                }
            );

    return 1;

    # $Init->getSession()->safechdir;

}

1;
