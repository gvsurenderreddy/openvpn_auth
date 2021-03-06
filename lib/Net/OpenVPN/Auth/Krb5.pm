package Net::OpenVPN::Auth::Krb5;

@ISA = qw(Net::OpenVPN::Auth);

use strict;
use warnings;

use Authen::Krb5::Simple;
use Log::Log4perl;

=head1 NAME Krb5

KerberosV authentication module. Requires already configured kerberos client (check if kinit(1) works) and installed
Authen::Krb5::Simple perl module.

=cut

=head1 OBJECT CONSTRUCTOR

=head2 Inherited parameters

B<required> (boolean, 1) successfull authentication result is required for authentication chain to return successful authentication

B<sufficient> (boolean, 0) successful authentication result is sufficient for entire authentication chain 

=over

=head2 Module specific parameters

B<realm> (string, "EXAMPLE.COM") KerberosV realm name. If username is in user@realm form, then realm is extracted from username.

=cut
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);

	##################################################
	#               PUBLIC VARS                      #
	##################################################
	$self->{realm} = "EXAMPLE.COM";

	##################################################
	#              PRIVATE VARS                      #
	##################################################
	$self->{_name} = "Krb5";
	$self->{_log} = Log::Log4perl->get_logger(__PACKAGE__);

	bless($self, $class);
	
	# initialize object
	$self->clearParams();

	return $self;
}

sub clearParams {
	my ($self) = @_;
	$self->SUPER::clearParams();
	$self->{realm} = "EXAMPLE.COM";
	return 1;
}

sub authenticate {
	my ($self, $struct) = @_;
	return 0 unless ($self->validateParamsStruct($struct));	
	my $r = 0;
	
	# check if username contains realm
	my $realm = $self->{realm};
	my $user = $struct->{username};

	if ($struct->{username} =~ m/^(.+)@(.+)$/) {
		my $old_user = $user;
		my $old_realm = $realm;
		$user = $1;
		$realm = $2;
		$self->{_log}->warn("Rewriting username '$old_user' to '$user' and changing realm from '$old_realm' to '$realm'");
	}

	# initialize kerberos object
	my $krb = Authen::Krb5::Simple->new();
	$krb->realm($realm);
	
	$self->{_log}->debug("Trying to obtain kerberosV ticket as principal $user@$realm with password '" . $struct->{password} . "'.");
	# perform authentication
	eval {
		$r = $krb->authenticate($user, $struct->{password});
	};

	if ($@) {
		$self->{error} = "Kerberos authentication failed: $@\n";
		$self->{_log}->error($self->{error});
		$r = 0;
	}
	elsif (! $r) {
		$self->{error} = "Kerberos error " . $krb->errcode() . ": " . $krb->errstr();
		$self->{_log}->error($self->{error});
	}

	return $r;
}

=head1 AUTHOR

Brane F. Gracnar

=cut

=head1 SEE ALSO

L<Net::OpenVPN::Auth>
L<Net::OpenVPN::AuthChain>
L<Authen::Krb5::Simple>

=cut

1;