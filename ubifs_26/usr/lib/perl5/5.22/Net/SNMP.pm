
package Net::SNMP;








use strict;


BEGIN 
{
   die('Perl version 5.6.0 or greater is required') if ($] < 5.006);
}


our $VERSION = v5.2.0;


use Net::SNMP::Dispatcher();
use Net::SNMP::PDU qw( :ALL );
use Net::SNMP::Security();
use Net::SNMP::Transport qw( :ports );


use Exporter();

our @ISA = qw( Exporter );

our @EXPORT = qw(
   INTEGER INTEGER32 OCTET_STRING OBJECT_IDENTIFIER IPADDRESS COUNTER
   COUNTER32 GAUGE GAUGE32 UNSIGNED32 TIMETICKS OPAQUE COUNTER64 NOSUCHOBJECT
   NOSUCHINSTANCE ENDOFMIBVIEW snmp_dispatcher 
);

our @EXPORT_OK = qw( snmp_event_loop oid_context_match );

our %EXPORT_TAGS = (
   asn1        => [ 
      qw( INTEGER INTEGER32 OCTET_STRING NULL OBJECT_IDENTIFIER SEQUENCE
          IPADDRESS COUNTER COUNTER32 GAUGE GAUGE32 UNSIGNED32 TIMETICKS
          OPAQUE COUNTER64 NOSUCHOBJECT NOSUCHINSTANCE ENDOFMIBVIEW
          GET_REQUEST GET_NEXT_REQUEST GET_RESPONSE SET_REQUEST TRAP
          GET_BULK_REQUEST INFORM_REQUEST SNMPV2_TRAP REPORT )
   ],
   debug       => [ 
      qw( DEBUG_ALL DEBUG_NONE DEBUG_MESSAGE DEBUG_TRANSPORT DEBUG_DISPATCHER
          DEBUG_PROCESSING DEBUG_SECURITY snmp_debug )
   ],
   generictrap => [ 
      qw( COLD_START WARM_START LINK_DOWN LINK_UP AUTHENTICATION_FAILURE
          EGP_NEIGHBOR_LOSS ENTERPRISE_SPECIFIC )
   ],
   snmp        => [
      qw( SNMP_VERSION_1 SNMP_VERSION_2C SNMP_VERSION_3 SNMP_PORT 
          SNMP_TRAP_PORT snmp_debug snmp_dispatcher snmp_dispatch_once
          snmp_type_ntop oid_base_match oid_lex_sort ticks_to_time ) 
   ],
   translate   => [
      qw( TRANSLATE_NONE TRANSLATE_OCTET_STRING TRANSLATE_NULL
          TRANSLATE_TIMETICKS TRANSLATE_OPAQUE TRANSLATE_NOSUCHOBJECT
          TRANSLATE_NOSUCHINSTANCE TRANSLATE_ENDOFMIBVIEW TRANSLATE_UNSIGNED
          TRANSLATE_ALL )
   ]
);

Exporter::export_ok_tags( qw( asn1 debug generictrap snmp translate ) );

$EXPORT_TAGS{ALL} = [ @EXPORT_OK ];


sub DEBUG_ALL()        { 0xff }  # All
sub DEBUG_NONE()       { 0x00 }  # None
sub DEBUG_MESSAGE()    { 0x02 }  # Message/PDU encoding/decoding
sub DEBUG_TRANSPORT()  { 0x04 }  # Transport Layer
sub DEBUG_DISPATCHER() { 0x08 }  # Dispatcher
sub DEBUG_PROCESSING() { 0x10 }  # Message Processing
sub DEBUG_SECURITY()   { 0x20 }  # Security


our $DEBUG = DEBUG_NONE;         # Debug mask 

our $DISPATCHER;                 # Dispatcher instance

our $BLOCKING = 0;               # Count of blocking objects

our $NONBLOCKING = 0;            # Count of non-blocking objects

BEGIN
{
   # Validate the creation of the Dispatcher object. 

   if (!defined($DISPATCHER = Net::SNMP::Dispatcher->instance)) {
      die('FATAL: Failed to create Dispatcher instance');
   }
}



sub new
{
   my ($class, %argv) = @_;

   # Create a new data structure for the object
   my $this = bless {
        '_callback'          =>  undef,           # Callback
        '_context_engine_id' =>  undef,           # contextEngineID
        '_context_name'      =>  undef,           # contextName
        '_delay'             =>  0,               # Message delay
        '_hostname'          =>  '',              # Hostname
        '_discovery_queue'   =>  [],              # Pending message queue
        '_error'             =>  undef,           # Error message
        '_nonblocking'       =>  FALSE,           # Blocking/non-blocking flag
        '_pdu'               =>  undef,           # Message/PDU object
        '_security'          =>  undef,           # Security Model object
        '_translate'         =>  TRANSLATE_ALL,   # Translation mask 
        '_transport'         =>  undef,           # Transport Domain object
        '_transport_argv'    =>  [],              # Transport constructor argv
        '_version'           =>  SNMP_VERSION_1,  # SNMP version
   }, $class;

   # Parse the passed arguments 

   my @transport = qw(
      -domain -dstaddr -dstport -hostname -localaddr -localport 
      -maxmsgsize -mtu -port -retries -srcaddr -srcport -timeout 
   );
   
   foreach (keys %argv) {

      if (/^-?debug$/i) {
         $this->debug(delete($argv{$_}));
      } elsif (/^-?nonblocking$/i) {
         $this->{_nonblocking} = (delete($argv{$_})) ? TRUE : FALSE;
      } elsif (/^-?translate$/i) {
         $this->translate(delete($argv{$_}));
      } elsif (/^-?version$/i) {
         $this->_version($argv{$_});
      } else {
         # Pull out arguments associated with the Transport Domain 
         my $key   = $_;
         my @match = grep(/^-?\Q$key\E$/i, @transport);
         if (@match == 1) {
            push(@{$this->{_transport_argv}}, $match[0], delete($argv{$key}));
         }
      }

      if (defined($this->{_error})) {
         $this->_object_type_count;
         return wantarray ? (undef, $this->{_error}) : undef;
      }

   }

   # Create a Security Model object

   ($this->{_security}, $this->{_error}) = Net::SNMP::Security->new(%argv); 
   if (!defined($this->{_security})) {
      $this->_object_type_count;
      return wantarray ? (undef, $this->{_error}) : undef;
   }
   $this->_error_clear;

   # We must validate the object type to prevent blocking and 
   # non-blocking object from existing at the same time.
 
   if (!defined($this->_object_type_validate)) {
      $this->_object_type_count;
      return wantarray ? (undef, $this->{_error}) : undef;
   }
     
   # Return the object and empty error message (in list context)
   wantarray ? ($this, '') : $this;
}

sub open
{
   my ($this) = @_;

   # Clear any previous errors
   $this->_error_clear;

   # Create a Transport Domain object
   ($this->{_transport}, $this->{_error}) = Net::SNMP::Transport->new(
      @{$this->{_transport_argv}}
   );

   if (!defined($this->{_transport})) {
      return $this->_error;
   }
   $this->_error_clear;

   # Keep a copy of the hostname 
   $this->{_hostname} = $this->{_transport}->dest_hostname;

   # Perform SNMPv3 authoritative engine discovery
   $this->_discovery if ($this->version == SNMP_VERSION_3);

   $this->{_transport};
}


sub session 
{
   my $class = shift;

   my ($this, $error) = $class->new(@_);

   if (defined($this)) {
      if (!defined($this->open)) {
         return wantarray ? (undef, $this->error) : undef;
      }
   }

   wantarray ? ($this, $error) : $this;
}

sub manager
{
   shift->session(@_);
}


sub close : locked : method
{
   my ($this) = @_;

   $this->_error_clear;
   $this->{_pdu}       = undef;
   $this->{_transport} = undef;
}


sub snmp_dispatcher() 
{
   $DISPATCHER->activate;
}

sub snmp_event_loop()
{
   warn
      sprintf(
         "snmp_event_loop() is deprecated, use snmp_dispatcher() instead at " .
         "%s line %d.\n", (caller(0))[1,2]
      );

   snmp_dispatcher;
}

sub snmp_dispatch_once()
{
   $DISPATCHER->one_event;
}


sub get_request : locked : method
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}


sub get_next_request : locked : method
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_next_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}


sub set_request : locked : method
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_set_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}


sub trap : locked : method
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -delay
                                          -enterprise
                                          -agentaddr
                                          -generictrap
                                          -specifictrap
                                          -timestamp
                                          -varbindlist  )], \@_, \@argv)))
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_trap(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;

   defined($this->{_error}) ? $this->_error : TRUE;
}


sub get_bulk_request : locked : method
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname
                                          -nonrepeaters 
                                          -maxrepetitions 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_bulk_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}


sub inform_request : locked : method
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_inform_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}


sub snmpv2_trap : locked : method
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -delay
                                          -contextengineid
                                          -contextname
                                          -varbindlist )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_snmpv2_trap(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;

   defined($this->{_error}) ? $this->_error : TRUE;
}


sub get_table : locked : method
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   # Validate the passed arguments.  For backwards compatiblity
   # see if the first argument is an OBJECT IDENTIFIER and then
   # act accordingly.

   if ((@_) && ($_[0] =~ /^\.?\d+\.\d+(?:\d+)*/)) {
      unshift(@_, '-baseoid');
   }

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -baseoid         
                                          -maxrepetitions  )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if ($argv[0] !~ /^\.?\d+\.\d+(?:\d+)*/) {
      return $this->_error(
         'Expected base OBJECT IDENTIFIER in dotted notation'
      );
   }

   # Create a new PDU.
   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   # Create table of values that need passed along with the
   # callbacks.  This just prevents a big argument list.

   my %argv = (
      base_oid   => $argv[0], 
      callback   => $this->{_pdu}->callback,
      repeat_cnt => 0,
      table      => undef,
      types      => undef,
      use_bulk   => FALSE
   );

   # Override the callback now that we have stored it.
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
         $this->_get_table_cb(\%argv); 
      }
   );

   # Determine if we are going to use get-next-requests or get-bulk-requests
   # based on the SNMP version and the -maxrepetitions argument.

   if ($this->version == SNMP_VERSION_1) {
      if (defined($argv[1])) {
         return $this->_error(
            'A max-repetitions value is not applicable when using SNMPv1'
         );
      }
   } else {
      $argv{use_bulk} = (defined($argv[1]) && $argv[1] <= 1) ? FALSE : TRUE;
   }    

   # Create either a get-next-request or get-bulk-request PDU.

   if (!$argv{use_bulk}) {

      # Set max_reps to be used as a limit for loop detection.
      $argv{max_reps} = 5;

      if (!defined($this->{_pdu}->prepare_get_next_request([$argv[0]]))) {
         return $this->_error($this->{_pdu}->error);
      }

   } else {

      # Store the max-repetitions value to be used.

      if (defined($argv[1])) {
         $argv{max_reps} = $argv[1];
      } else {
         $argv{max_reps} = $this->_msg_size_max_reps;
      }

      if (!defined(
            $this->{_pdu}->prepare_get_bulk_request(
                0, $argv{max_reps}, [$argv[0]]
            )
         )) 
      {
         return $this->_error($this->{_pdu}->error);
      }
   }

   $this->_send_pdu;
}


sub get_entries : locked : method
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   # Validate the passed arguments.  

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname
                                          -entryoid
                                          -columns
                                          -startindex
                                          -endindex  
                                          -maxrepetitions       
                                          -rowcallback     )], \@_, \@argv)))
   {
      return $this->_error;
   }

   if (ref($argv[1]) ne 'ARRAY') {
      return $this->_error('Expected array reference for column list');
   }

   if (!scalar(@{$argv[1]})) {
      return $this->_error('Empty column list specified');
   }

   # The syntax of get_entries() changes between release 4.1.0 and
   # release 4.1.1.  For backwards compatibility, we assume the old
   # syntax is being used if the "-entryoid" argument is present
   # and we silently convert to the new syntax.  

   if (defined($argv[0])) {

      if ($argv[0] !~ /^\.?\d+\.\d+(?:\.\d+)*$/) {
         return $this->_error(
            'Expected entry OBJECT IDENTIFIER in dotted notation'
         );
      }

      my $columns = {};

      for (@{$argv[1]}) {
         if (!/^\d+$/) {
            return $this->_error(
               'Expected positive numeric value in column list [%s]', $_
            );
         }
         if (exists($columns->{$_})) {
            return $this->_error('Duplicate entry in column list [%s]', $_);
         } else {
            $columns->{$_} = $_;
         }
      }

      # Now create the new syntax for the columns list

      $argv[1] = [];

      for (sort { $a <=> $b } (keys(%{$columns}))) {
         push(@{$argv[1]}, join('.', $argv[0], $_));      
      }

   }

   # Validate the column list. 
 
   for (@{$argv[1]}) {
      if (!/^\.?\d+\.\d+(?:\.\d+)*$/) {
         return $this->_error(
            'Expected column OBJECT IDENTIFIER in dotted notation [%s]', $_
         );
      }
   }

   my $start_index = '';

   if (defined($argv[2])) {
      if ($argv[2] !~ /^\d+(?:\.\d+)*$/) {
         return $this->_error('Expected start index in dotted notation');
      }
      my @subids = split('\.', $argv[2]);
      if ($subids[-1] > 0) { 
         $subids[-1]--;
      } else {
         pop(@subids);
      }
      $start_index = (@subids) ? join('.', @subids) : '';
   }

   if (defined($argv[3])) {
      if ($argv[3] !~ /^\d+(?:\.\d+)*$/) {
         return $this->_error('Expected end index in dotted notation');
      }
      if (defined($argv[2])) {
         if (_index_cmp($argv[2], $argv[3]) > 0) {
            return $this->_error('End index cannot be less than start index');
         }
      }
   }

   # Undocumented and unsupported "-rowcallback" argument.

   if (defined($argv[5])) {
      if (ref($argv[5]) eq 'CODE') {
         $argv[5] = [$argv[5]];
      } elsif ((ref($argv[5]) ne 'ARRAY') || (ref($argv[5]->[0]) ne 'CODE')) {
         return $this->_error('Invalid row callback format');
      }
   }   

   # Create a new PDU.
   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   # Create table of values that need passed along with the
   # callbacks.  This just prevents a big argument list.

   my %argv = (
      callback     => $this->{_pdu}->callback,
      columns      => $argv[1],
      end_index    => $argv[3],
      entries      => undef,
      last_index   => '0', 
      row_callback => $argv[5],
      start_index  => $argv[2],
      types        => undef,
      use_bulk     => FALSE 
   );

   # Override the callback now that we have stored it.
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
         $this->_get_entries_cb(\%argv);
      }
   );
   
   # Create the varBindList by indexing each column with the start index.

   my $vbl = [ map { join('.', $_, $start_index) } @{$argv{columns}} ]; 

   # Determine if we are going to use get-next-requests or get-bulk-requests
   # based on the SNMP version and the -maxrepetitions argument.

   if ($this->version == SNMP_VERSION_1) {
      if (defined($argv[4])) {
         return $this->_error(
            'A max-repetitions value is not applicable when using SNMPv1'
         );
      }
   } else {
      $argv{use_bulk} = (defined($argv[4]) && $argv[4] <= 1) ? FALSE : TRUE;
   }

   # Create either a get-next-request or get-bulk-request PDU.

   if (!$argv{use_bulk}) {

      if (!defined($this->{_pdu}->prepare_get_next_request($vbl))) {
         return $this->_error($this->{_pdu}->error);
      }

   } else {

      # Store the max-repetitions value to be used.

      if (defined($argv[4])) {
         $argv{max_reps} = $argv[4];
      } else {
         # Scale the max-repetitions based on the number of columns.
         $argv{max_reps} =
            int($this->_msg_size_max_reps / @{$argv{columns}}) + 1;
      }

      if (!defined(
            $this->{_pdu}->prepare_get_bulk_request(0, $argv{max_reps}, $vbl)
         ))
      {
         return $this->_error($this->{_pdu}->error);
      }
   }

   $this->_send_pdu;
}


sub version : locked : method
{
   my ($this) = @_;

   return $this->_error('SNMP version is not modifiable') if (@_ == 2);

   $this->{_version}; 
}


sub error : locked : method
{
   $_[0]->{_error} || '';
}


sub hostname : locked : method
{
   $_[0]->{_hostname};
}


sub error_status : locked : method
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->error_status : 0;
}


sub error_index : locked : method
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->error_index : 0;
}


sub var_bind_list : locked : method
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->var_bind_list : undef;
}


sub var_bind_names : locked : method
{
   defined($_[0]->{_pdu}) ? @{$_[0]->{_pdu}->var_bind_names} : ();
}


sub var_bind_types : locked : method
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->var_bind_types : undef;
}


sub timeout : locked : method
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Domain defined');
   }

   my $timeout = $this->{_transport}->timeout(@_);

   defined($timeout) ? $timeout : $this->_error($this->{_transport}->error);
}


sub retries : locked : method
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Domain defined');
   }

   my $retries = $this->{_transport}->retries(@_);

   defined($retries) ? $retries : $this->_error($this->{_transport}->error);
}


sub max_msg_size : locked : method
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Domain defined');
   }

   my $max_size = $this->{_transport}->max_msg_size(@_);

   defined($max_size) ? $max_size : $this->_error($this->{_transport}->error);
}

sub mtu
{
   shift->max_msg_size(@_);
}


sub translate : locked : method
{
   my ($this, $mask) = @_;

   if (@_ == 2) {

      if (ref($mask) ne 'ARRAY') {

         # Behave like we did before, do (not) translate everything
         $this->_translate_mask($_[1], TRANSLATE_ALL);

      } else {

         # Allow the user to turn off and on specific translations.  An
         # array is used so the order of the arguments controls how the
         # mask is defined.

         my @argv = @{$mask};
         my $arg;

         while (defined($arg = shift(@argv))) {
            if ($arg =~ /^-?all$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_ALL);
            } elsif ($arg =~ /^-?none$/i) { 
               $this->_translate_mask(!(shift(@argv)), TRANSLATE_ALL);
            } elsif ($arg =~ /^-?octet_?string$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_OCTET_STRING);
            } elsif ($arg =~ /^-?null$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_NULL);
            } elsif ($arg =~ /^-?timeticks$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_TIMETICKS);
            } elsif ($arg =~ /^-?opaque$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_OPAQUE);
            } elsif ($arg =~ /^-?nosuchobject$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_NOSUCHOBJECT);
            } elsif ($arg =~ /^-?nosuchinstance$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_NOSUCHINSTANCE);
            } elsif ($arg =~ /^-?endofmibview$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_ENDOFMIBVIEW);
            } elsif ($arg =~ /^-?unsigned$/i) {
               $this->_translate_mask(shift(@argv), TRANSLATE_UNSIGNED);
            } else {
               return $this->_error("Invalid translate argument '%s'", $arg);
            }
         }

      }

      DEBUG_INFO("translate = 0x%02x", $this->{_translate});
   }

   $this->{_translate};
}


sub debug
{
   my (undef, $mask) = @_;

   if (@_ == 2) {

      $DEBUG = ($mask =~ /^\d+$/) ? $mask : ($mask) ? DEBUG_ALL : DEBUG_NONE;

      eval { Net::SNMP::Message->debug($DEBUG & DEBUG_MESSAGE);              }; 
      eval { Net::SNMP::Transport->debug($DEBUG & DEBUG_TRANSPORT);          }; 
      eval { Net::SNMP::Dispatcher->debug($DEBUG & DEBUG_DISPATCHER);        };
      eval { Net::SNMP::MessageProcessing->debug($DEBUG & DEBUG_PROCESSING); }; 
      eval { Net::SNMP::Security->debug($DEBUG & DEBUG_SECURITY);            };

   }

   $DEBUG;
}

sub snmp_debug($)
{
   debug(undef, $_[0]);
}

sub pdu : locked : method
{
   $_[0]->{_pdu};
}

sub nonblocking : locked : method
{
   $_[0]->{_nonblocking};
}

sub security : locked : method
{
   $_[0]->{_security};
}

sub transport : locked : method
{
   $_[0]->{_transport};
}


sub oid_base_match($$)
{
   my ($base, $oid) = @_;

   $base || return FALSE;
   $oid  || return FALSE;

   $base =~ s/^\.//o;
   $oid  =~ s/^\.//o;

   $base = pack('N*', split('\.', $base));
   $oid  = pack('N*', split('\.', $oid));

   (substr($oid, 0, length($base)) eq $base) ? TRUE : FALSE;
}

sub oid_context_match($$)
{
   oid_base_match($_[0], $_[1]);
}


sub oid_lex_sort(@)
{
   return @_ unless (@_ > 1);

   map  { $_->[0] } 
   sort { $a->[1] cmp $b->[1] } 
   map  {
      my $oid = $_; 
      $oid =~ s/^\.//o;
      $oid =~ s/ /\.0/og;
      [$_, pack('N*', split('\.', $oid))]
   } @_;
}


sub snmp_type_ntop($)
{
   asn1_itoa($_[0]);
}


sub ticks_to_time($)
{
   asn1_ticks_to_time($_[0]);
}

sub VERSION
{
   # Provide our own VERSION method so that the version returns 
   # as a floating point number instead of a v-string.

   my $version = eval { 
      sprintf('%d.%03d%03d', unpack('C3', shift->UNIVERSAL::VERSION(@_))); 
   };

   if ($@) {
      local $_ = $@;
      s/at(.*)/sprintf("at %s line %s\n", (caller(0))[1], (caller(0))[2])/es;
      die $_;
   } 

   $version;
}

sub DESTROY
{
   my ($this) = @_;

   # We decrement the object type count when the object goes out of
   # existance.  We assume that _object_type_count() was called for
   # every creation or else we die.

   if ($this->{_nonblocking}) {
      if (--$NONBLOCKING < 0) {
         die('FATAL: Invalid non-blocking object count');
      }
   } else {
      if (--$BLOCKING < 0) {
         die('FATAL: Invalid blocking object count');
      }
   }
}


sub _send_pdu
{
   my ($this) = @_;

   # Check to see if we are still in the process of discovering the
   # authoritative SNMP engine.  If we are, queue the PDU if we are 
   # running in non-blocking mode.

   if (($this->{_nonblocking}) && (!$this->{_security}->discovered)) {
      push(@{$this->{_discovery_queue}}, [$this->{_pdu}, $this->{_delay}]);
      return TRUE;
   }

   # Hand the PDU off to the Dispatcher
   $DISPATCHER->send_pdu($this->{_pdu}, $this->{_delay});

   # Activate the dispatcher if we are blocking
   snmp_dispatcher() unless ($this->{_nonblocking});

   # Return according to blocking mode 
   ($this->{_nonblocking}) ? TRUE : $this->var_bind_list;
}

sub _pdu_create
{
   my ($this) = @_;

   # Create the new PDU
   ($this->{_pdu}, $this->{_error}) = Net::SNMP::PDU->new(
      -version   => $this->{_version},
      -security  => $this->{_security},
      -transport => $this->{_transport},
      -translate => $this->{_translate},
      -callback  => $this->_callback_closure,
      defined($this->{_context_engine_id}) ? 
         (-contextengineid => $this->{_context_engine_id}) : (),
      defined($this->{_context_name}) ?
         (-contextname     => $this->{_context_name})      : (),
   );

   if (!defined($this->{_pdu})) {
      return $this->_error;
   }
   $this->_error_clear;

   # Return the PDU
   $this->{_pdu};
}
    

sub _version
{

   # Clear any previous error message
   $_[0]->_error_clear;

   # Allow the user some flexability
   my $supported = {
      '1'       => SNMP_VERSION_1,
      'v1'      => SNMP_VERSION_1,
      'snmpv1'  => SNMP_VERSION_1,
      '2c'      => SNMP_VERSION_2C,
      'v2c'     => SNMP_VERSION_2C,
      'snmpv2c' => SNMP_VERSION_2C,
      '3'       => SNMP_VERSION_3,
      'v3'      => SNMP_VERSION_3,
      'snmpv3'  => SNMP_VERSION_3
   };

   if (@_ == 2) {
      my @match = grep(/^\Q$_[1]/i, keys(%{$supported})); 
      if (@match > 1) {
         return $_[0]->_error('Ambiguous SNMP version [%s]', $_[1]);
      }
      if (@match != 1) {
         return $_[0]->_error('Unknown or invalid SNMP version [%s]', $_[1]);
      }
      $_[1] = $_[0]->{_version} = $supported->{$match[0]};
   }

   $_[0]->{_version};
}

sub _prepare_argv
{

   my $obj_args = {
      -callback        => \&_callback,          # non-blocking only
      -contextengineid => \&_context_engine_id, # v3 only
      -contextname     => \&_context_name,      # v3 only
      -delay           => \&_delay,             # non-blocking only
   };

   my %argv;

   # For backwards compatibility, check to see if the first 
   # argument is an OBJECT IDENTIFIER in dotted notation.  If it
   # is, assign it to the -varbindlist argument.

   if ((@{$_[2]}) && ($_[2]->[0] =~ /^\.?\d+\.\d+(?:\d+)*/)) {
      $argv{-varbindlist} = $_[2];
   } else {
      %argv = @{$_[2]};
   }

   # Go through the passed argument list and see if the argument is
   # allowed.  If it is, see if it applies to the object and has a 
   # matching method call or add it the the new argv list to be 
   # returned by this method.

   my %new_args;

   foreach my $key (keys(%argv)) {
      my @match = grep(/^-?\Q$key\E$/i, @{$_[1]});
      if (@match == 1) {
         if (exists($obj_args->{$match[0]})) {
            if (!defined($_[0]->${\$obj_args->{$match[0]}}($argv{$key}))) {
               return $_[0]->_error;
            }
         } else {
            $new_args{$match[0]} = $argv{$key};   
         }
      } else {
         return $_[0]->_error("Invalid argument '%s'", $key);
      }
   }

   # Create a new ordered unnamed argument list based on the allowed 
   # list passed, ignoring those that applied to the object.

   foreach (@{$_[1]}) {
      next if exists($obj_args->{$_});
      push(@{$_[3]}, exists($new_args{$_}) ? $new_args{$_} : undef);
   }

   $_[3];
}


sub _callback
{
   my ($this, $callback) = @_;
  
   # We validate the callback argument and then create an anonymous 
   # array where the first element is the subroutine reference and 
   # the second element is an array reference containing arguments 
   # to pass to the subroutine.

   if (!$this->{_nonblocking}) {
      return $this->_error('Callbacks are not applicable to blocking objects');
   }
 
   my @argv;

   if (!defined($callback)) {
      $this->{_callback} = undef;
      return TRUE;
   } elsif ((ref($callback) eq 'ARRAY') && (ref($callback->[0]) eq 'CODE')) {
      @argv = @{$callback};
      $callback = shift(@argv);
   } elsif (ref($callback) ne 'CODE') {
      return $this->_error('Invalid callback format');
   }

   $this->{_callback} = [$callback, \@argv]; 
}

sub _callback_closure
{
   my ($this) = @_;

   # When a response message is received, the Dispatcher will create
   # a new PDU object and assign the callback to that object.  The
   # callback is then executed passing a reference to the PDU object 
   # as the first argument.  We use a closure to assign that passed 
   # reference to the Net:SNMP object and then invoke the user defined 
   # callback.

   if (!$this->{_nonblocking}) {

      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if ($this->{_pdu}->error);
      };

   } else {

      return undef unless defined ($this->{_callback});

      my $callback = $this->{_callback}->[0];
      my @argv = @{$this->{_callback}->[1]};

      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if ($this->{_pdu}->error);
         $callback->($this, @argv);
      };

   }

}

sub _context_engine_id
{
   my ($this, $context_engine_id) = @_;

   $this->_error_clear;

   if ($this->version != SNMP_VERSION_3) {
      return $this->_error('contextEngineID only supported in SNMPv3');
   }

   if (!defined($context_engine_id)) {
      $this->{_context_engine_id} = undef; 
      TRUE;
   } elsif ($context_engine_id =~ /^(?i:0x)?([a-fA-F0-9]{10,64})$/) {
      $this->{_context_engine_id} = pack('H*', length($1) % 2 ? '0'.$1 : $1);
   } else {
      $this->_error('Invalid contextEngineID format specified');
   }
}

sub _context_name
{
   my ($this, $context_name) = @_;

   $this->_error_clear;

   if ($this->version != SNMP_VERSION_3) {
      return $this->_error('contextName only supported in SNMPv3');
   }

   if (length($context_name) > 32) {
      return $this->_error(
         'Invalid contextName length [%d octets]', length($context_name) 
      );
   }

   $this->{_context_name} = $context_name;
}

sub _delay
{
   my ($this, $delay) = @_;

   $this->_error_clear;

   if (!$this->{_nonblocking}) {
      return $this->_error('Delay not applicable to blocking objects');   
   }

   if ($delay !~ /^\d+(?:\.\d+)?$/) {
      return $this->_error('Invalid delay value [%s]', $delay);
   }

   $this->{_delay} = $delay;
}

sub _object_type_validate
{
   my ($this) = @_;

   # Since both non-blocking and blocking objects use the same
   # Dispatcher instance, allowing both objects type to exist at
   # the same time would cause problems.  This method is called 
   # by the constructor to prevent this situation from happening.

   if (($this->{_nonblocking}) && ($BLOCKING)) {
      return $this->_error(
         'Cannot create non-blocking objects when blocking objects exist'
      );
   } elsif ((!$this->{_nonblocking}) && ($NONBLOCKING)) {
      return $this->_error(
         'Cannot create blocking objects when non-blocking objects exist'
      );
   }

   # Now we can bump up the object count
   $this->_object_type_count;
}

sub _object_type_count
{ 
   # This method must be called any time an object is created.  The
   # destructor will decrement this count.

   ($_[0]->{_nonblocking}) ? $NONBLOCKING++ : $BLOCKING++;
} 

sub _discovery
{
   my ($this) = @_;

   return TRUE if ($this->{_security}->discovered);

   # RFC 3414 - Section 4: "Discovery... ...may be accomplished by
   # generating a Request message with a securityLevel of noAuthNoPriv,
   # a msgUserName of zero-length, a msgAuthoritativeEngineID value of
   # zero length, and the varBindList left empty."

   # Create a new PDU
   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   # Create the callback and assign it to the PDU
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         if ($this->{_pdu}->error) {
            $this->_error($this->{_pdu}->error . ' during discovery');
         }
         $this->_discovery_engine_id_cb; 
      }
   );

   # Prepare an empty get-request
   if (!defined($this->{_pdu}->prepare_get_request)) {
      return $this->_error($this->{_pdu}->error);
   }

   # Send the PDU
   $DISPATCHER->send_pdu($this->{_pdu}, 0);

   snmp_dispatcher() unless ($this->{_nonblocking});

   ($this->{_error}) ? $this->_error : TRUE;
}

sub _discovery_engine_id_cb
{
   my ($this) = @_;

   # "The response to this message will be a Report message containing 
   # the snmpEngineID of the authoritative SNMP engine...  ...with the 
   # usmStatsUnknownEngineIDs counter in the varBindList."  If another 
   # error is returned, we assume snmpEngineID discovery has failed.

   if ($this->{_error} !~ /usmStatsUnknownEngineIDs/) {

      # Discovery of the snmpEngineID has failed, clear the 
      # current PDU and the Transport Domain so no one can use 
      # this object to send messages.
 
      $this->{_pdu}       = undef;
      $this->{_transport} = undef;

      # Inform the command generator about the current error.
      while (my $q = shift(@{$this->{_discovery_queue}})) {
         $q->[0]->status_information($this->{_error});
      }

      return $this->_error;
   }

   # Clear the usmStatsUnknownEngineIDs error
   $this->_error_clear;

   # If the security model indicates that discovery is complete,
   # we send any pending messages and return success.  If discovery
   # is not complete, we probably need to synchronize with the
   # remote authoritative engine.

   if ($this->{_security}->discovered) {

      DEBUG_INFO('discovery complete');

      # Discovery is complete, send any pending messages
      while (my $q = shift(@{$this->{_discovery_queue}})) {
         $DISPATCHER->send_pdu(@{$q});
      }

      return TRUE;
   }

   # "If authenticated communication is required, then the discovery
   # process should also establish time synchronization with the
   # authoritative SNMP engine.  This may be accomplished by sending
   # an authenticated Request message..."

   # Create a new PDU
   if (!defined($this->_pdu_create)) {
      return $this->_error;
   }

   # Create the callback and assign it to the PDU
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         if ($this->{_pdu}->error) {
            $this->_error($this->{_pdu}->error . ' during synchronization');
         }
         $this->_discovery_synchronization_cb;
      }
   );

   # Prepare an empty get-request
   if (!defined($this->{_pdu}->prepare_get_request)) {
      return $this->_error($this->{_pdu}->error);
   }

   # Send the PDU
   $DISPATCHER->send_pdu($this->{_pdu}, 0);

   snmp_dispatcher() unless ($this->{_nonblocking});

   ($this->{_error}) ? $this->_error : TRUE;
}

sub _discovery_synchronization_cb
{
   my ($this) = @_;

   # "The response... ...will be a Report message containing the up 
   # to date values of the authoritative SNMP engine's snmpEngineBoots 
   # and snmpEngineTime...  It also contains the usmStatsNotInTimeWindows
   # counter in the varBindList..."  If another error is returned, we 
   # assume that the synchronization has failed.

   if (($this->{_security}->discovered) &&
       ($this->{_error} =~ /usmStatsNotInTimeWindows/))
   {
      $this->_error_clear;
    
      DEBUG_INFO('discovery and synchronization complete');

      # Discovery is complete, send any pending messages
      while (my $q = shift(@{$this->{_discovery_queue}})) {
         $DISPATCHER->send_pdu(@{$q});
      }

      return TRUE;
   }

   # If we received the usmStatsNotInTimeWindows report or no error, but 
   # we are still not synchronized, provide a generic error message.

   if ((!$this->{_error}) || ($this->{_error} =~ /usmStatsNotInTimeWindows/)) {
      $this->_error_clear;
      $this->_error('Time synchronization failed during discovery');
   }

   DEBUG_INFO('synchronization failed');

   # Synchronization has failed, clear the current PDU and 
   # the Transport Domain so no one can use this object to 
   # send messages.

   $this->{_pdu}       = undef;
   $this->{_transport} = undef;

   # Inform the command generator about the current error.
   while (my $q = shift(@{$this->{_discovery_queue}})) {
      $q->[0]->status_information($this->{_error});
   }

   $this->_error;
}


sub _translate_mask
{
   my ($this, $enable, $mask) = @_;

   # Define the translate bitmask for the object based on the
   # passed truth value and mask.

   if (@_ != 3) {
      return $this->{_translate};
   }

   if ($enable) {
      $this->{_translate} |= $mask;  # Enable
   } else {
      $this->{_translate} &= ~$mask; # Disable
   }
}

sub _msg_size_max_reps
{
   my ($this) = @_;

   # Use the maxMsgSize of the object to produce a max-repetitions
   # value.  This is an attempt to avoid exceeding the maxMsgSize
   # in the responses to get-bulk-requests.  The scaling factor
   # of 0.017 produces a value of 25 with the default maxMsgSize of
   # 1472. This was the old hardcoded value used by get_table().
 
   if (defined($this->{_transport})) {
      int($this->{_transport}->max_msg_size * 0.017);
   } else {
      25;
   }
}

sub _get_table_cb
{
   my ($this, $argv) = @_;

   # Use get-next-requests or get-bulk-requests until the response is
   # not a subtree of the base OBJECT IDENTIFIER.  Return the table only
   # if there are no errors other than a noSuchName(2) error since the
   # table could be at the end of the tree.  Also return the table when
   # the value of the OID equals endOfMibView(2) when using SNMPv2c.

   # Assign the user callback to the PDU.  
   $this->{_pdu}->callback($argv->{callback});

   # Check to see if the var_bind_list is defined (was there an error?)

   if (defined(my $result = $this->var_bind_list)) {

      my $types = $this->var_bind_types;
      my @oids  = oid_lex_sort(keys(%{$result}));
      my ($next_oid, $end_of_table) = (undef, FALSE);

      while (@oids) { 

         $next_oid = shift(@oids);

         # Add the entry to the table

         if (oid_base_match($argv->{base_oid}, $next_oid)) {

            if (!exists($argv->{table}->{$next_oid})) {
               $argv->{table}->{$next_oid} = $result->{$next_oid};
               $argv->{types}->{$next_oid} = $types->{$next_oid};
            } elsif ($types->{$next_oid} == ENDOFMIBVIEW) {
               $end_of_table = TRUE;
            } else {
               $argv->{repeat_cnt}++;
            }

            # Check to make sure that the remote host does not respond
            # incorrectly causing the requests to loop forever.

            if ($argv->{repeat_cnt} > $argv->{max_reps}) {
               $this->{_pdu}->var_bind_list(undef);
               $this->{_pdu}->status_information(
                  'Loop detected with table on remote host'
               ); 
               return;
            }

         } else {
            $end_of_table = TRUE;
         }

      } 

      # Queue the next request if we are not at the end of the table.

      if (!$end_of_table) {
       
         my $pdu = $this->{_pdu};

         # Create a new PDU. 
         if (!defined($this->_pdu_create)) {
            $this->{_pdu} = $pdu;
            $this->{_pdu}->var_bind_list(undef);
            $this->{_pdu}->status_information($this->error);
            return;
         }

         # Override the callback
         $this->{_pdu}->callback(
            sub {
               $this->{_pdu} = $_[0];
               $this->_error_clear;
               $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
               $this->_get_table_cb($argv);
            }
         );

         if (!$argv->{use_bulk}) {
            if (!defined(
                  $this->{_pdu}->prepare_get_next_request([$next_oid])
               )) 
            {
               $this->{_pdu}->var_bind_list(undef);
               $this->{_pdu}->status_information($this->{_pdu}->error);
               return; 
            }
         } else {
            if (!defined(
                  $this->{_pdu}->prepare_get_bulk_request(
                     0, $argv->{max_reps}, [$next_oid]
                  )
               ))
            {
               $this->{_pdu}->var_bind_list(undef);
               $this->{_pdu}->status_information($this->{_pdu}->error);
               return; 
            }
         } 

         # Send the next PDU with no delay.
         return $DISPATCHER->send_pdu($this->{_pdu}, 0) ? TRUE : $this->_error;
      }

      # Copy the table to the var_bind_list.
      $this->{_pdu}->var_bind_list($argv->{table}, $argv->{types});

   }

   # Check for noSuchName(2) error.
   if ($this->error_status == 2) {
      $this->{_pdu}->error(undef);
      $this->{_pdu}->var_bind_list($argv->{table}, $argv->{types});
   }

   if (!defined($argv->{table}) && (!$this->{_pdu}->error)) {
      $this->{_pdu}->error( 
         'Requested table is empty or does not exist'
      );
   }

   # Notify the command generator to process the results.
   $this->{_pdu}->process_response_pdu;
}

sub _get_entries_cb
{
   my ($this, $argv) = @_;

   # Assign the user callback to the PDU.
   $this->{_pdu}->callback($argv->{callback});

   # Check to see if the varBindList is defined (was there an error?)

   if (defined(my $result = $this->var_bind_list)) {

      my $types      = $this->var_bind_types;
      my $max_index  = $argv->{last_index};
      my $last_entry = TRUE;
      my @vb_names   = $this->var_bind_names;
      my $vb_index   = @vb_names;

      # Iterate through the response OBJECT IDENTIFIERs.  The response(s)
      # will (should) be grouped in the same order as the columns that
      # were requested.  We use this assumption to map the response(s) to
      # get-next/bulk-requests.

      while ($vb_index > 0) {
     
         my @row;
         my $row_index;

         # Match up the responses to the requested columns.

         for (my $col_num = 0; $col_num <= $#{$argv->{columns}}; $col_num++) { 

            my $column = $argv->{columns}->[$col_num];

            if ($vb_names[-$vb_index] =~ /$column\.(\d+(:?\.\d+)*)/) { 

               my $index = $1;
               DEBUG_INFO('index: %s', $index);

               # Validate the index of the response.
 
               if ((defined($argv->{start_index})) &&
                   (_index_cmp($index, $argv->{start_index}) < 0))
               {

                  DEBUG_INFO(
                     'index [%s] not past start index [%s]',
                     $index, $argv->{start_index}
                  );

               } elsif ((defined($argv->{end_index})) &&
                        (_index_cmp($index, $argv->{end_index}) > 0))
               { 

                  DEBUG_INFO(
                     'last_entry: index [%s] past end index [%s]',
                     $index, $argv->{end_index}
                  );
                  $last_entry = TRUE;

               } else {

                  # To handle "holes" in the conceptual row, checks
                  # need to be made so that the lowest index for
                  # each group of responses is used.

                  $row_index = $index unless defined($row_index);

                  my $index_cmp = _index_cmp($index, $row_index);

                  if ($index_cmp == 0) {

                     # The index for this response entry matches
                     # so fill in the corresponding row entry.

                     $row[$col_num] = $vb_names[-$vb_index];

                  } elsif ($index_cmp < 0) {

                     # The index for this response is less than
                     # the current index, so we throw out 
                     # everything and start over.

                     DEBUG_INFO('new minimum index [%s]', $index);
                     @row = ();
                     $row_index = $index;
                     $row[$col_num] = $vb_names[-$vb_index];

                  } else {

                     # Skip this entry, there must be a "hole"
                     # in the row the was requested.

                     DEBUG_INFO(
                        'index [%s] greater than current minimum [%s]',
                        $index, $row_index
                     ); 
                  }

               }              

            } else {

               # The response does not map to the the request, there 
               # could be a "hole" or we are out of entries. 

               DEBUG_INFO(
                  'last_entry: column mismatch [%s]', $vb_names[-$vb_index] 
               );
               $last_entry = TRUE;
            }

            if ($vb_index-- < 1) {
               DEBUG_INFO('column number / oid number mismatch');
               @row = ();
               last; 
            }

         }

         # Now store the results for the conceptual row.

         if (@row) {

            foreach my $oid (@row) {
               next unless defined($oid);
               if (!exists($argv->{entries}->{$oid})) {
                  $last_entry = FALSE;
                  $argv->{entries}->{$oid} = $result->{$oid};
                  $argv->{types}->{$oid}   = $types->{$oid};
               } else {
                  DEBUG_INFO('not adding duplicate [%s]', $oid);
               }
            }

            # Upcall with the row information if so configured.

            if (defined($argv->{row_callback})) {
               
               my @argv = @{$argv->{row_callback}};
               my $cb   = shift(@argv);
         
               # Add the "values" found for each column to 
               # the front of the callback argument list.
 
               for (my $num = $#{$argv->{columns}}; $num >= 0; $num--) {
                  if (defined($row[$num])) {
                     unshift(@argv, $argv->{entries}->{$row[$num]});
                  } else {
                     unshift(@argv, undef);
                  }
               }

               # Prepend the index for the conceptual row.
               unshift(@argv, $row_index);
              
               eval { $cb->(@argv); }; 

            }

            # Store the maximum index found to be used 
            # for the next get-next/bulk-request.

            if (_index_cmp($row_index, $max_index) > 0) {
               $max_index = $row_index;
            }

         }

      }

      # Make sure we are not stuck (looping) on a single index.

      my $index_cmp = _index_cmp($max_index, $argv->{last_index});

      if ((!$last_entry) && (!$index_cmp)) {
         $last_entry = TRUE;
         DEBUG_INFO('last_entry: duplicate entries');
      } elsif ($index_cmp > 0) {
         $argv->{last_index} = $max_index;
      }


      # If we have not reached the last requested entry, 
      # generate another get-next/bulk-request message.

      if (!$last_entry) {

         my $pdu = $this->{_pdu};

         # Create a new PDU
         if (!defined($this->_pdu_create)) {
            $this->{_pdu} = $pdu;
            $this->{_pdu}->error($this->error); 
            goto callback_complete;
         }

         # Override the callback
         $this->{_pdu}->callback(
            sub {
               $this->{_pdu} = $_[0];
               $this->_error_clear;
               $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
               $this->_get_entries_cb($argv);
            }
         );

         # Create the varBindList by indexing each column OBJECT
         # IDENTIFIER with the maximum index found in the response.

         my $vbl = [ map { join('.', $_, $max_index) } @{$argv->{columns}} ];

         if (!$argv->{use_bulk}) {
            if (!defined($this->{_pdu}->prepare_get_next_request($vbl))) {
               goto callback_complete; 
            }
         } else {
            if (!defined(
                  $this->{_pdu}->prepare_get_bulk_request(
                     0, $argv->{max_reps}, $vbl
                  )
               ))
            {
               goto callback_complete;
            }
         }

         # Send the next PDU with no delay.
         return $DISPATCHER->send_pdu($this->{_pdu}, 0); 
      }

      # Copy the rows to the var_bind_list.
      $this->{_pdu}->var_bind_list($argv->{entries}, $argv->{types});

   }

   callback_complete:

   # Check for noSuchName(2) error
   if ($this->error_status == 2) {
      $this->{_pdu}->error(undef);
      $this->{_pdu}->var_bind_list($argv->{entries}, $argv->{types});
   }

   if (!defined($argv->{entries}) && (!$this->{_pdu}->error)) {
      $this->{_pdu}->error('Requested entries are empty or do not exist');
   }

   # If there was an error and the row callback is defined upcall.

   if ($this->{_pdu}->error && defined($argv->{row_callback})) {

      my @argv = @{$argv->{row_callback}};
      my $cb   = shift(@argv);

      for (my $num = 0; $num <= $#{$argv->{columns}} + 1; $num++) {
         unshift(@argv, undef);
      }

      eval { $cb->(@argv); };

   }

   # Notify the command generator to process the results.
   $this->{_pdu}->process_response_pdu;
}

sub _index_cmp($$)
{
   pack('N*', split('\.', $_[0])) cmp pack('N*', split('\.', $_[1]));
}

sub _error
{
   my $this = shift;

   # If the PDU callback is still defined when an error occurs, it
   # needs to be cleared to prevent the closure from holding up the
   # reference count of the object that created the closure.

   if (defined($this->{_pdu}) && defined($this->{_pdu}->callback)) {
      $this->{_pdu}->callback(undef);
   }

   if (!defined($this->{_error})) {
      $this->{_error} = (@_ > 1) ? sprintf(shift(@_), @_) : $_[0];
      if ($this->debug) {
         printf("error: [%d] %s(): %s\n",
            (caller(0))[2], (caller(1))[3], $this->{_error}
         );
      }
   }

   return;
}

sub _error_clear
{
   $_[0]->{_error} = undef;
}

sub require_version
{
   # As of Exporter v5.562, the require_version() method does not
   # handle x.y.z version strings properly.  We provide our own 
   # method to handle our x.y.z version requirements.

   my ($this, $wanted) = @_;

   my $pkg = ref($this) || $this;

   if ($wanted =~ /(\d+)\.(\d{1,3})\.(\d{1,3})/) {
      $wanted = sprintf('%d.%03d%03d', $1, $2, $3);
   } elsif ($wanted =~ /(\d+)\.(\d+)/) {
      $wanted = sprintf('%d.%03d', $1, $2);
   }

   my $version = eval { $pkg->UNIVERSAL::VERSION($wanted); };

   if ($@) {
      local $_ = $@;
      s/at(.*)/sprintf("at %s line %s\n", (caller(2))[1], (caller(2))[2])/es;
      die $_;
   }
 
   $version;
}

sub DEBUG_INFO
{
   return unless $DEBUG;

   printf(
      sprintf('debug: [%d] %s(): ', (caller(0))[2], (caller(1))[3]) .
      ((@_ > 1) ? shift(@_) : '%s') . 
      "\n",
      @_
   );

   $DEBUG;
}



1; # [end Net::SNMP]
