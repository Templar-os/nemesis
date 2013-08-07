package MiddleWare::metasploit;
use Moose;
use Resources::Exploit;
use Resources::Node;
use Nemesis::Inject;

our $VERSION = '0.1a';
our $AUTHOR  = "mudler";
our $MODULE  = "Metasploit Module";
our $INFO    = "<www.dark-lab.net>";

#Funzioni che fornisco.
our @PUBLIC_FUNCTIONS =
    qw(start clear sessionlist call test generate matchExpl);    #NECESSARY

nemesis module {
    $self->MSFRPC( $Init->getModuleLoader->loadmodule("MSFRPC") );
    $self->DB( $Init->getModuleLoader->loadmodule("DB")->connect );
}

#Attributo Processo del demone MSFRPC
has 'Process' => ( is => "rw" );

#Risorsa MSFRPC che mi fornirà il modo di connettermi a MSFRPC
has 'MSFRPC' => ( is => "rw" );
has 'DB'     => ( is => "rw" );

sub start() {
    my $self = shift;
    return 1 if ( $self->Process && $self->Process->is_running );

    my $Io = $self->Init->getIO();

    my $processString =
          'msfrpcd -U '
        . $self->MSFRPC->Username . ' -P '
        . $self->MSFRPC->Password . ' -p '
        . $self->MSFRPC->Port . ' -S';
    $Io->print_info("Starting msfrpcd service.")
        ;    #AVVIO il demone msfrpc con le configurazioni della risorsa
    my $Process = $Init->getModuleLoader->loadmodule('Process')
        ;    ##Carico il modulo process
    $Process->set(
        type => 'daemon',         # tipologia demone
        code => $processString    # linea di comando...
    );
    if ( $Process->start() ) {    #Avvio
        $self->Process($Process)
            ;    #Nell'attributo processo del plugin ci inserisco il processo
        if ( $Process->is_running ) {
            $Io->print_info("Service msfrcpd started")
                ;    #Controllo se si è avviato
            $Io->process_status($Process);    #Stampo lo status
            $Io->print_alert(
                "Now you have to give some time to metasploit to be up and running.."
            );
        }
    }

}

sub safe_database() {
    my $self = shift;
    my $result = $self->DB->search( class => "Resources::Exploit" );

    while ( my $block = $result->next ) {
        foreach my $item (@$block) {
            my $result2 = $self->DB->search( module => $item->module );
            while ( my $block2 = $result2->next ) {
                foreach my $item2 (@$block2) {
                    if ( $item ne $item2 ) {
                        $self->DB->delete($item2);
                        $Init->getIO->debug("Deleting $item2");
                    }
                }
            }
        }
    }

}

sub LaunchExploitOnNode() {
    my $self    = shift;
    my $Node    = shift;
    my $Exploit = shift;
    my @OPTIONS = ( "exploits", $Exploit->module, );
#Posso usare le promises, oppure
#master polling ogni 10 minuti.
    my $Options = $self->MSFRPC->options( "exploits", $Exploit->module );
    my $Payloads = $self->MSFRPC->payloads( $Exploit->module );
    $Init->getIO->debug_dumper( \$Options );
    $Init->getIO->debug_dumper( \$Payloads );

}

sub event_Resources__Exploit {
    my $self = shift;
    $Init->io->debug("Exploit generated correctly!");
}

sub generate() {
    my $self = shift;

    #  $self->start if ( !$self->Process or !$self->Process->is_running );
    $self->DB( $Init->getModuleLoader->loadmodule("DB")->connect )
        ;    #Lo userò spesso.
    my $response = $self->MSFRPC->call('module.exploits');
    if ( !exists( $response->{'modules'} ) ) {
        $self->Init->getIO->print_alert("Cannot sync with meta");
        return;
    }
    my @EXPL_LIST = @{ $response->{'modules'} };

    $self->Init->getIO()
        ->print_alert("Syncing db with msf exploits, this can take a while");
    $self->Init->getIO()
        ->print_info(
        "There are " . scalar(@EXPL_LIST) . " exploits in metasploit" );
    my $result = $self->DB->search( { class => "Resources::Exploit" } );
    my $Counter = 0;
    while ( my $block = $result->next ) {
        foreach my $item (@$block) {
            $Counter++;
        }
    }
    $self->Init->getIO()
        ->print_info("$Counter of them already are in the database ");

    $Counter = 0;
    foreach my $exploit (@EXPL_LIST) {

        my $Information = $self->MSFRPC->info( "exploits", $exploit );
        my $Options = $self->MSFRPC->options( "exploits", $exploit );
        $self->MSFRPC->parse_result;

        my $result = $self->DB->search( { module => $exploit } );
        my $AlreadyThere = 0;
        while ( my $block = $result->next ) {
            foreach my $item (@$block) {
                $AlreadyThere = 1;
                last;
            }
        }
        if ( $AlreadyThere == 0 ) {
            $self->Init->getIO()->debug("Adding $exploit to Exploit DB");
            my @Targets = values %{ $Information->{'targets'} };
            my @References = map { $_ = join( "|", @{$_} ); }
                @{ $Information->{'references'} };
            $self->Init->getIO()->debug( join( " ", @Targets ) . " targets" );
            my $Expla = Resources::Exploit->new(
                type          => "exploits",
                module        => $exploit,
                rank          => $Information->{'rank'},
                description   => $Information->{'description'},
                name          => $Information->{'name'},
                targets       => \@Targets,
                references    => \@References,
                default_rport => $Options->{'RPORT'}->{'default'}
            );
            $self->DB->add($Expla);
            $Counter++;
        }
    }
    $self->Init->getIO()->print_info(" $Counter added");

    #   $self->safe_database;

}

sub test() {
    my $self = shift;

    $self->LaunchExploitOnNode(
        Resources::Node->new( ip => "127.0.0.1" ),
        Resources::Exploit->new(
            type   => "exploits",
            module => "auxiliary/admin/backupexec/dump"
        )
    );

}

sub matchExpl() {
    my $self   = shift;
    my $String = shift;
    my @Objs   = $self->DB->searchRegex(
        class  => "Resources::Exploit",
        module => $String
    );

    $self->Init->getIO->print_tabbed(
        "Found a total of " . scalar(@Objs) . " objects for /$String/i", 3 );
    foreach my $item (@Objs) {
        $self->Init->getIO->print_tabbed(
            "Found " . $item->module . " " . $item->name, 4 );
    }
    return @Objs;

}

sub matchNode() {

    my $self = shift;
    my $Node = shift;
    $self->Init->getIO->print_info(
        "Matching the node against Metasploit database");
    foreach my $port ( @{ $Node->ports } ) {
        my ( $porta, $service ) = split( /\|/, $port );
        foreach my $expl (
            ( $self->matchExpl($service), $self->matchPort($porta) ) )
        {
            $self->Init->getIO->print_info(
                "Exploit targets: " . join( " ", @{ $expl->targets } ) );

            foreach my $target ( @{ $expl->targets } ) {
                my $os = $Node->os;
                if ( $Node->os =~ /embedded/ ) {
                    $os = "linux";
                }    #it's a good assumption, i know
                if ( $target =~ /$os/i or $target =~ /Automatic/ ) {
                    $self->Init->getIO->print_info("$target match");
                    $Node->attachments->insert($expl);
                    last;
                }
            }
        }
    }
    return $Node;
}

sub matchPort() {
    my $self   = shift;
    my $String = shift;
    my $Objs   = $self->DB->search( default_rport => $String );
    $self->Init->getIO->print_tabbed(
        "Searching a matching exploit for port $String", 3 );

    my @Return;
    while ( my $chunk = $Objs->next ) {
        for my $item (@$chunk) {
            $self->Init->getIO->print_tabbed(
                "Found " . $item->module . " " . $item->name, 4 );
            push( @Return, $item );
        }
    }

    return @Return;

}

sub sessionlist() {
    my $self    = shift;
    my @OPTIONS = (
        "auxiliary",
        "server/browser_autopwn",
        {   LHOST   => "0.0.0.0",
            SRVPORT => "8080",
            URIPATH => "/"
        }
    );

    #my $response = $self->call( "session.list", @OPTIONS );
    $self->MSFRPC->call("session.list");

}

sub call() {
    my $self   = shift;
    my $String = shift;
    $self->MSFRPC->call($String);
}

sub clear() {
    my $self = shift;
    $self->Process->destroy() if ( $self->Process );

#Il metodo clear viene chiamato quando chiudiamo tutto, dunque se ho un processo attivo, lo chiudo!
}

sub event_tcp() {

    # my $IO=$Init->io;
    # my $PrivIp;
    # my $PubIp;
    # my $SourcePort;
    # my $DestPort;
    # foreach my $Packet(@Packet_info){
    #      if( $Packet->isa("NetPacket::IP") ) {
    #             my $InfoIP=Net::IP->new($Packet->{src_ip});
    #             my $SrcType=$InfoIP->iptype;
    #              $InfoIP=Net::IP->new($Packet->{dest_ip});
    #             my  $DstType=$InfoIP->iptype;
    #             if($SrcType eq "PRIVATE"  ) {
    #                 $PrivIp=$SrcType;
    #             }else {
    #                 $PubIp=$SrcType;
    #             }
    #             if($DstType eq "PRIVATE"){
    #                 $PrivIp=$DstType;
    #             } else {
    #                 $PubIp=$DstType;
    #             }
    #         } elsif( $Packet->isa("NetPacket::TCP") ) {
    #             $SourcePort=$Packet->{src_port};
    #             $DestPort=$Packet->{dest_port};
    #         }
    # }

# if(defined($PrivIp)){
#                        my $DBHost;
#    $Init->io->info("searching for matches for $PrivIp : $SourcePort/$DestPort");

    #    my $results=$self->DB->search(ip => $PrivIp);

    #    while( my $chunk = $results->next ){
    #                  foreach my $foundhost (@$chunk){
    #                   $DBHost=$foundhost;
    #                   last;
    #               }
    #     }

#   foreach my $FoundExploit(($self->matchPort($SourcePort),$self->matchPort($DestPort))){
#   #Update Database with new information
#     #Launch Exploit

    #    }
    # }
}

1;
