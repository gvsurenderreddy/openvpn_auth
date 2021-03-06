package Net::OpenVPN::AuthDaemon;

@ISA = qw (
	Net::Server::PreFork
);

use strict;
use warnings;

use Log::Log4perl;
use Net::Server::PreFork;
use File::Basename qw(basename);

use vars qw($MYNAME);

use Net::OpenVPN::AuthChain;

use constant MAXLINES => 20;
use constant MAX_LINE_LENGTH => 1024;

##################################################
#             OBJECT CONSTRUCTOR                 #
##################################################

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};

	##################################################
	#               PUBLIC VARS                      #
	##################################################
	$self->{auth_timeout} = 5;
	$self->{umask} = umask();

	##################################################
	#              PRIVATE VARS                      #
	##################################################
	$self->{_log} = Log::Log4perl->get_logger(__PACKAGE__);
	$self->{_myname} = "AuthDaemon";

	bless($self, $class);
	return $self;
};

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub getError {
	my ($self) = @_;
	return $self->{error};
}

sub post_bind_hook {
	my ($self) = @_;
	if (defined ($self->{umask})) {
		umask($self->{umask});
	}

	# relocate stdout, stderr
	tie *STDERR, $self;
	tie *STDOUT, $self;

	# close stdin and reopen it on null device
	close(STDIN);
	open(STDIN, File::Spec->devnull());
}

sub process_request {
	my ($self) = @_;
	my $params = undef;
	my $result_str = "NO Invalid credentials.";
	
	# set up signal handler
	local $SIG{ALRM} = sub {
		print {$self->{server}->{client}} "NO Authentication timed out.\n";
		$self->{_log}->warn("Authentication timed out.");
		$self->_cleanup();
		exit 0;
	};

	# set alarm
	alarm($self->{auth_timeout});
	
	# read client data
	my $struct = $self->readStruct();

	# authenticate
	my $r = $self->{_chain}->authenticate($struct);
	if ($r) {
		$result_str = "OK Valid credentials.";
		$self->{_log}->info("Successfull authentication for user '" . $struct->{username} . "'.");
	} else {
		$self->{_log}->info("Unsuccessful authentication for user '" . $struct->{username}. "'.");
	}

	# reset alarm
	alarm(0);

	# write response back to client...
	print {$self->{server}->{client}} $result_str, "\n";

	# ... and shutdown client's socket...
	$self->_cleanup();

	return 1;
}

sub write_to_log_hook {
	my $self = shift;
	my $code = shift;
	
	if ($code <= 1) {
		$self->{_log}->info(@_);
	} else {
		$self->{_log}->debug(@_)
	}

	return 1;
}

sub setChain {
	my ($self, $obj) = @_;
	$self->{error} = "";
	unless (defined $obj && ref($obj) && $obj->isa("Net::OpenVPN::AuthChain")) {
		$self->{error} = "Invalid chain module.";
		return 0;
	}
	unless ($obj->isValidChain()) {
		$self->{error} = "Invalid chain: " . $obj->getError();
		return 0;
	}
	$self->{_chain} = $obj;
	return 1;
}

sub getChain {
	my ($self) = @_;
	$self->{error} = "";
	unless (defined $self->{_chain}) {
		$self->{error} = "Chain object is not assigned.";
		return undef;
	}
	return $self->{_chain};
}

sub getName {
	my ($self) = @_;
	return $self->{_myname};
}

sub setName {
	my ($self, $name) = @_;
	$self->{error} = "";
	unless (defined $name) {
		$self->{error} = "Invalid daemon name.";
		return 0;
	}
	$self->{_myname} = $name;
	return 1;
}

sub readStruct {
	my ($self) = @_;
	my $struct = {};
	$self->resetStruct($struct);

	my $i = 0;
	while ($i < MAXLINES && defined(my $line = $self->{server}->{client}->getline())) {
		$i++;
		$line = substr($line, 0, MAX_LINE_LENGTH);
		$line =~ s/\s+$//g;
		$line =~ s/^\s+//g;
		last unless (length($line));

		my @tmp = split(/=/, $line);
		my $key = shift(@tmp);
		$struct->{$key}	= join("=", @tmp);
	}
	
	if ($self->{_log}->is_debug()) {
		my $str = "";
		foreach my $key (sort keys %{$struct}) {
			$str .= " '$key' => '" . $struct->{$key} . "'";	
		}
		$self->{_log}->debug("Readed structure: " . $str);
	}

	return $struct;
}

sub resetStruct {
	my $self = shift;
	$_[0] = {
		username => '',
		password => '',
		untrusted_ip => '',
		untrusted_port => 0,
	};
	
	return 1;
}

# IO::Handle methods (used to catch output written by die && stuff)
sub TIEHANDLE {
	my $self = shift;
	return $self;
}

sub PRINT {
	my $self = shift;
	$self->{_log}->warn("Catched output to STDOUT/STDERR: ", @_);
	$self->{_log}->warn("This should not happen! Possible couses: Missing perl modules (running in chroot? Define \$extra_modules); OR BUG in your validation functions, if you're using AuthStruct module; OR BUG in openvpn_authd.pl/it's libraries.");
	return 1;
}

sub _cleanup {
	my ($self) = @_;

	if (defined $self->{server}->{client}) {
		$self->{server}->{client}->flush();
		$self->{server}->{client}->shutdown(2);
	}

	return 1;
}

=head1 AUTHOR

Brane F. Gracnar

=cut

=head1 SEE ALSO

L<Net::OpenVPN::Auth>
L<Net::OpenVPN::AuthChain>

=cut

1;
