#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;

sub main {
    my $pkg  = shift;
    my $self = bless {}, $pkg;
    my $force = 0;

    GetOptions( $self->getopt_spec ) or $self->usage->();

    delete @ENV{qw(PERL_MM_OPT PERL_MB_OPT)};
    $ENV{PATH} .= ':.';

    my $available = $self->available_rpms();
    my $wanted    = $self->wanted_rpms();

    ## delete returns the values deleted
    my @have      = grep { defined } delete @$wanted{ keys %$available };
    my @fulfilled = map  { $available->{ $_->[0] } } @have;

    warn sprintf(qq{already have %s\n}, $self->available_message($_)) for @fulfilled;

    warn sprintf(qq{needing %s\n}, $self->needed_message($_)) for values(%$wanted);

    if ($force) {
	warn sprintf(qq{forcing build of '%s' as %s\n}, $_->[0], $self->needed_message( $_)) for @have;
	$wanted->{ $_->[0] } = $_ for @have;
    }

    if ($self->{'run_build'}){
	$self->run_cpan2rpm( $_ ) for values(%$wanted);
    }

    return 0;
}

sub available_message {
    my ($self, $a) = @_;
    return sprintf(q{%s version %s for %s from %s}, @$a[0,2,1,3]);
}

sub needed_message {
    my ($self, $n) = @_;
    return sprintf(q{module %s version %s is required}, @$n[1,2]);
}
sub available_rpms {
    my ($self) = @_;
    my %available;
    open(my $fh, '-|', 'yum list -C perl-* 2>/dev/null');
    while(my $line = <$fh>) {
	chomp($line);
	next unless $line =~ /^perl-/;
	my ($fullname, $version, $source) = split(/\s+/, $line);
	my ($name, $arch) = split(/\./, $fullname);
	$available{$name} = [ $name, $arch, $version, $source];
    }
    return \%available;
}

sub wanted_rpms {
    my $self = shift;
    my %wanted;

    open(my $csv, '<', $self->modules_file) or return \%wanted;
    while(my $line = <$csv>) {
	next if $line =~ m/^#/; 
	chomp($line);
	my ($perl_name, $version, $url) =
	    split(/,\s?/, $line);

	(my $rpmname = $perl_name) =~ s/::/-/g;
	$rpmname     = "perl-$rpmname";

	$wanted{ $rpmname } = [ $rpmname, $perl_name, $version || 0, $url ];
    }

    return \%wanted;
}

sub run_cpan2rpm {
    my ($self, $module) = @_;

    my @cmd;
    push @cmd, qw(cpan2rpm --no-prfx);
    push @cmd, '--name', $module->[0];
    push @cmd, '--rpmbuild', '/workspace/hrards/ensembl/69/cpan2rpm/cpan2rpmbuild';

    if ($module->[2]){
	push @cmd, '--version', $module->[2];
    }

    if ($module->[3]){
	push @cmd, $module->[3];
    } else {
	push @cmd, $module->[1];
    }
    #warn "@cmd\n";
    system(@cmd);
}

sub modules_file :lvalue { $_[0]->{'modules.file'}; }

sub getopt_spec {
    my $self = shift;
    $self->modules_file = 'modules.list';
    return (
	'help'   => $self->usage,
	'file=s' => \$self->{'modules.file'},
	'build'  => \$self->{'run_build'},
	);
}

sub usage { sub { exec 'perldoc', '-t', $0; }; }

exit ( __PACKAGE__->main(@ARGV) ) unless caller();
