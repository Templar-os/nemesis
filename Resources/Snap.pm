package Resources::Snap;
use Class::Accessor "antlers";

use DateTime;

has 'was'  => ( is => "rw" );
has 'now'  => ( is => "rw" );
has 'date' => ( is => "rw", default => sub { DateTime->now; } );

1;
