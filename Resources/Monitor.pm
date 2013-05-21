use MooseX::Declare;

use Nemesis::Inject;
class Resources::Monitor{
use Resources::Dispatcher;
use Net::Frame::Simple;
use Net::Frame::Dump::Online;

	has 'Device' => (is=>"rw",default=>"wlan0");
	has 'Filter' => (is=>"rw",default=>"");
	has 'Promiscuous' => (is=>"rw",default=>"1");
	has 'Dispatcher' => (is=>"rw");
	has 'File'		 => (is=>"rw", default=>undef);
	has 'SnifferInstance' => (is=>"rw");
	has 'Dispatcher'	 => (is=>"rw");
	nemesis_resource;


	$SIG{'TERM'}=sub { exit; };

	method run(){
		my $d=$self->Init->getModuleLoader->loadmodule("Dispatcher");
		$self->Dispatcher($d);
		$self->Init->getIO()->print_info("Listening on ".$self->Device. " with ".$self->Filter." Promisc:".$self->Promiscuous);
		
		my $Dump = Net::Frame::Dump::Online->new(
		   dev            => $self->Device,
		   timeoutOnNext  => 3,
		   timeout        => 0,
		   promisc        => $self->Promiscuous,
		   unlinkOnStop   => 1,
		   file           => $self->File,
		   filter         => $self->Filter,
		   overwrite      => 0,
		   isRunning      => 0,
		   keepTimestamp  => 0,
		   onRecvCount    => -1,
		   frames         => [],
		);
		$self->SnifferInstance($Dump);

		$Dump->start;
 

		while (1) {
		   if (my $f = $Dump->next) {
		      # my $raw            = $f->{raw};
		      # my $firstLayerType = $f->{firstLayer};
		      # my $timestamp      = $f->{timestamp};
       		  my $oSimple = Net::Frame::Simple->newFromDump($f);
       		#  $Init->io->debug($oSimple->print);
		      $d->dispatch_packet($oSimple);
		   }
		}

		$Init->getIO()->print_alert("Exited from loop, something happened");
	}

	method stop(){
		$self->SnifferInstance->stop();
	}

		

}
1;