package Plugin::metasploit;
{

    use Nemesis::Inject;
    use Moose;
    use Resources::Exploit;

    my $VERSION = '0.1a';
    my $AUTHOR  = "mudler";
    my $MODULE  = "Metasploit Module";
    my $INFO    = "<www.dark-lab.net>";

    #Funzioni che fornisco.
    my @PUBLIC_FUNCTIONS =
        qw(start clear sessionlist call test generate matchExpl)
        ;    #NECESSARY
#Attributo Processo del demone MSFRPC
    has 'Process' => (is=>"rw"); 
#Risorsa MSFRPC che mi fornirà il modo di connettermi a MSFRPC
    has 'MSFRPC'  => (is=>"rw"); 
    has 'DB' => (is=>"rw");
    nemesis_module;

  sub prepare(){
            
           #    $self->DB($Init->getModuleLoader->loadmodule("DB")->connect); #Lo userò spesso.
  }

    sub start(){
my $self=shift;
        return 1 if($self->Process && $self->Process->is_running);


        $self->DB($Init->getModuleLoader->loadmodule("DB")->connect) if !$self->DB;
        my $Io    = $Init->getIO();

        $self->MSFRPC($Init->getModuleLoader->loadmodule("MSFRPC")); #Carico la risorsa MSFRPC

        my $processString =
              'msfrpcd -U '
            . $self->MSFRPC->Username . ' -P '
            . $self->MSFRPC->Password . ' -p '
            . $self->MSFRPC->Port . ' -S';
        $Io->print_info("Starting msfrpcd service."); #AVVIO il demone msfrpc con le configurazioni della risorsa
        my $Process = $Init->getModuleLoader->loadmodule('Process'); ##Carico il modulo process
        $Process->set(
            type => 'daemon',    # tipologia demone
            code => $processString # linea di comando...
        );
        $Process->start(); #Avvio
        $self->Process($Process); #Nell'attributo processo del plugin ci inserisco il processo
        if ( $Process->is_running ) {
            $Io->print_info("Service msfrcpd started"); #Controllo se si è avviato
            $Io->process_status($Process); #Stampo lo status
            $Io->print_alert(
                "Now you have to give some time to metasploit to be up and running.."
            );
        }

    }

    sub safe_database(){
my $self=shift;
        my $result=$self->DB->search(class => "Resources::Exploit");


        while( my $block = $result->next ) {
            foreach my $item ( @$block ) {
                my $result2=$self->DB->search(module=>$item->module);
                        while( my $block2 = $result2->next ) {
                          foreach my $item2 ( @$block2 ) {  
                           if($item ne $item2){
                                $self->DB->delete($item2);
                                $Init->getIO->debug("Deleting $item2");
                            }
                          }
                        }
            }
        }

  



    }


    sub LaunchExploitOnNode(){
        my $self=shift;
        my $Node=shift;
        my $Exploit=shift;
          my @OPTIONS = (
            "exploits",
            $Exploit->module,
           );
 
         my $Options = $self->MSFRPC->options("exploits",$Exploit->module);
         my $Payloads = $self->MSFRPC->payloads($Exploit->module);
         $Init->getIO->debug_dumper(\$Options);
                  $Init->getIO->debug_dumper(\$Payloads);


    }

    sub generate() {
        my $self=shift;
        $self->start if(!$self->Process or !$self->Process->is_running);

        my $response=$self->MSFRPC->call('module.exploits');
        if(!exists($response->{'modules'})){
            $self->Init->getIO->print_alert("Cannot sync with meta");
            return;
        }
        my @EXPL_LIST=@{$response->{'modules'}};

        $self->Init->getIO()->print_alert("Syncing db with msf exploits, this can take a while");
        $self->Init->getIO()->print_info("There are " .scalar(@EXPL_LIST). " exploits in metasploit");
        my $result=$self->DB->search(class => "Resources::Exploit");
            my $Counter=0;
                while( my $block = $result->next ) {
                    foreach my $item ( @$block ) {
                        $Counter++;
                    }
                }
        $self->Init->getIO()->print_info("$Counter of them already are in the database ");

        $Counter=0;
        foreach my $exploit (@EXPL_LIST) {

            my $Information = $self->MSFRPC->info("exploits",$exploit);
            my $Options = $self->MSFRPC->options("exploits",$exploit);
            $self->MSFRPC->parse_result;

            my $result=$self->DB->search(module => $exploit);
            my $AlreadyThere=0;
                while( my $block = $result->next ) {
                    foreach my $item ( @$block ) {
                        $AlreadyThere=1;
                    }
                }
            if($AlreadyThere == 0) {
                $self->Init->getIO()->debug("Adding $exploit to Exploit DB");
                my @Targets  =  values % { $Information->{'targets'} };
                my @References = map { $_ = join("|", @{$_} ); } @{$Information->{'references'}};
                $self->Init->getIO()->debug(join(" ",@Targets)." targets");
                $self->DB->add(Resources::Exploit->new(
                                type=> "exploits",
                                module=>$exploit,
                                rank=> $Information->{'rank'},
                                description=>$Information->{'description'},
                                name=>$Information->{'name'},
                                targets=>\@Targets,
                                references=>\@References,
                                default_rport=> $Options->{'RPORT'}->{'default'}
                                ));
                $Counter++;
            }
        }
        $self->Init->getIO()->print_info(" $Counter added");

     #   $self->safe_database;

    }

    sub test(){
my $self=shift;

    $self->LaunchExploitOnNode(Resources::Node->new(
                ip => "127.0.0.1"
                ),Resources::Exploit->new(
                                type=> "exploits",
                                module=> "auxiliary/admin/backupexec/dump"
                                ));

    }

   sub matchExpl(){
my $self=shift;
my $String=shift;
       my @Objs=$self->DB->searchRegex(class=> "Resources::Exploit",module=> $String);

$self->Init->getIO->print_tabbed("Found a total of ".scalar(@Objs)." objects for /$String/i",3);
        foreach my $item ( @Objs ) {
            $self->Init->getIO->print_tabbed("Found ".$item->module." ".$item->name,4);
        }
        return @Objs;
                
    }


    sub matchNode(){

        my $self=shift;
        my $Node=shift;
        $self->Init->getIO->print_info("Matching the node against Metasploit database");
        foreach my $port(@{$Node->ports}){
            my ($porta,$service) = split(/\|/,$port);
            foreach my $expl (($self->matchExpl($service),$self->matchPort($porta))){
                $self->Init->getIO->print_info("Exploit targets: ".join(" ",@{$expl->targets}));

                foreach my $target(@{$expl->targets}){
                    my $os=$Node->os;
                    if($Node->os =~ /embedded/){$os="linux";} #it's a good assumption, i know
                    if($target=~/$os/i or $target=~/Automatic/){
                        $self->Init->getIO->print_info("$target match");
                        $Node->attachments->insert($expl);
                        last;
                    }
                }
            }
        }
        return $Node;
    }

    sub matchPort(){
my $self=shift;
my $String=shift;
       my $Objs=$self->DB->search(default_rport=> $String);
       $self->Init->getIO->print_tabbed("Searching a matching exploit for port $String",3);

       my @Return;
        while( my $chunk = $Objs->next ){
            for my $item (@$chunk) {
            $self->Init->getIO->print_tabbed("Found ".$item->module." ".$item->name,4);
            push(@Return,$item);
            }
        }
     
        return @Return;
                
    }

    sub sessionlist(){
my $self=shift;
        my @OPTIONS = (
            "auxiliary",
            "server/browser_autopwn",
            {   LHOST   => "0.0.0.0",
                SRVPORT => "8080",
                URIPATH => "/"
            }
        );
        #my $response = $self->call( "session.list", @OPTIONS );
        $self->MSFRPC->call( "session.list" );

    }

    sub call(){
        my $self=shift;
        my $String=shift;
        $self->MSFRPC->call($String);
    }

    sub clear(){
        my $self=shift;
        $self->Process->destroy() if($self->Process) ;
        #Il metodo clear viene chiamato quando chiudiamo tutto, dunque se ho un processo attivo, lo chiudo!
    }

    sub event_tcp(){
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
    
}

1;
__END__
my $CONF = {
    VARS => {
        MSFRPCD_USER => 'spike',
        MSFRPCD_PASS => 'spiketest',
        MSFRPCD_PORT => 5553,
        HOST         => '127.0.0.1',
        MSFRPCD_API  => '/api/',
    }
};

#nemesis_module;
#TODO: Rendere il modulo esterno, creando un'altro oggetto Moose per l'interazione con msfrpcd
nemesis_module;

sub prepare {
    $Init->getIO()
        ->print_info( "Testing " . __PACKAGE__ . " prepare() function" )
        ;    #This is called after initialization of Init
}

sub call() {
    my $self        = shift;
    my $meth        = shift;
    my @opts        = @_;
    my $UserAgent   = LWP::UserAgent->new;
    my $MessagePack = Data::MessagePack->new();
    $self->start()
        if ( !exists( $self->{'process'}->{'msfrpcd'} ) );
    my $URL =
          'http://'
        . $CONF->{'VARS'}->{'HOST'} . ":"
        . $CONF->{'VARS'}->{'MSFRPCD_PORT'}
        . $CONF->{'VARS'}->{'MSFRPCD_API'};
    if ( $meth ne 'auth.login' and !$self->{_authenticated} ) {
        $self->msfrpc_login();
    }
    unshift @opts, $self->{_token} if ( exists( $self->{_token} ) );
    unshift @opts, $meth;
    my $HttpRequest = new HTTP::Request( 'POST', $URL );
    $HttpRequest->content_type('binary/message-pack');
    $HttpRequest->content( $MessagePack->pack( \@opts ) );
    my $res = $UserAgent->request($HttpRequest);
    $self->parse_result($res);
    croak( "MSFRPC: Could not connect to " . $URL )
        if $res->code == 500;
    croak("MSFRPC: Request failed ($meth)") if $res->code != 200;
    $Init->getIO()->debug_dumper( $MessagePack->unpack( $res->content ) );
    return $MessagePack->unpack( $res->content );
}

sub browser_autopwn() {
    my $self    = shift;
    my @OPTIONS = (
        "auxiliary",
        "server/browser_autopwn",
        {   LHOST   => "0.0.0.0",
            SRVPORT => "8080",
            URIPATH => "/"
        }
    );
    $response = $self->call( "module.execute", @OPTIONS );
    if ( exists( $response->{'uuid'} ) ) {
        $Init->getIO()
            ->print_alert(
            "Now you have to wait until browser_autopwn finishes loading exploits."
            );
        $self->parse_result($response);
        $Init->getIO()->print_tabbed( "Your URL : http://0.0.0.0:8080", 2 );
    }
    else {
        $Init->getIO()->print_error("Something went wrong");
    }
}

sub msfrpc_login() {
    my $self = shift;
    my $user = $CONF->{'VARS'}->{'MSFRPCD_USER'};
    my $pass = $CONF->{'VARS'}->{'MSFRPCD_PASS'};
    my $ret  = $self->call( 'auth.login', $user, $pass );
    if ( $ret->{'result'} eq 'success' ) {
        $self->{_token}         = $ret->{'token'};
        $self->{_authenticated} = 1;
    }
    else {
        $Init->getIO()->debug_dumper($ret);
        $Init->getIO()->print_error("Failed auth with MSFRPC");
    }
}

sub help() {    #NECESSARY
    my $self    = shift;
    my $IO      = $self->{'core'}->{'IO'};
    my $section = $_[0];
    $IO->print_title( $MODULE . " Helper" );
    if ( $section eq "configure" ) {
        $IO->print_title("nothing to configure here");
    }
}

sub start {
    my $self  = shift;
    my $which = $_[0];
    my $Io    = $Init->getIO();
    my $code =
          'msfrpcd -U '
        . $CONF->{'VARS'}->{'MSFRPCD_USER'} . ' -P '
        . $CONF->{'VARS'}->{'MSFRPCD_PASS'} . ' -p '
        . $CONF->{'VARS'}->{'MSFRPCD_PORT'} . ' -S';
    $Io->print_info("Starting msfrpcd service.");
    my $Process = $Init->getModuleLoader->loadmodule('Process');
    $Process->set(
        type => 'daemon',    # forked pipeline
        code => $code,
        Init => $Init,
    );
    $Process->start();
    $Io->debug( $Io->generate_command($code) );
    $self->{'process'}->{'msfrpcd'} = $Process;
    if ( $Process->is_running ) {
        $Io->print_info("Service msfrcpd started");
        $Io->process_status($Process);
        $Io->print_alert(
            "Now you have to give some time to metasploit to be up and running.."
        );
    }
}

sub clear() {
    my $self = shift;
    if ( exists( $self->{'process'}->{'msfrpcd'} ) ) {
        $self->{'process'}->{'msfrpcd'}->destroy();
        delete $self->{'process'}->{'msfrpcd'};
    }
    else {
        $Init->getIO()->print_alert("Process already stopped");
    }
}

sub status {
    my $self = shift;
    my $process;
    foreach my $service ( keys %{ $self->{'process'} } ) {
        $self->process_status($service);
    }
}

sub parse_result() {
    my $self = shift;
    my $pack = $_[0];
    if ( exists( $pack->{'error'} ) ) {
        $Init->getIO()
            ->print_error("Something went wrong with your MSFRPC call");
        $Init->getIO()->print_error( "Code error: " . $pack->{'error_code'} );
        $Init->getIO()->print_error( "Message: " . $pack->{'error_message'} );
        foreach my $trace ( $pack->{'error_backtrace'} ) {
            $Init->getIO()->print_tabbed( "Backtrace: " . $trace, 2 );
        }
    }
    else {
        if ( exists( $pack->{'job_id'} ) ) {
            $Init->getIO()->print_info( "Job ID: " . $pack->{'job_id'} );
        }
    }
} 