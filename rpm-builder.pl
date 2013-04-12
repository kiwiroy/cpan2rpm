#!/usr/bin/perl

use strict;
use warnings;

use File::Spec;
use FindBin;
use Getopt::Long;

sub main {
    my $pkg  = shift;
    my $self = bless {}, $pkg;
    my $force = 0;

    GetOptions( $self->getopt_spec ) or $self->usage->();

    delete @ENV{qw(PERL_MM_OPT PERL_MB_OPT)};
    $ENV{PATH} .= ':.';
    ## Fix for XML::SAX::Expat - See their Makefile.PL and FAQ @ http://perl.arix.com/cpan2rpm/
    $ENV{SKIP_SAX_INSTALL} = 1;
    my $wanted    = $self->wanted_rpms();
    my $available = $self->available_rpms( map { [ $_->[1], $_->[2] ] } values %$wanted );

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

    warn sprintf(qq{** success %s **\n}, $_) for @{ $self->{'success'} };
    warn sprintf(qq{** failed %s **\n},  $_) for @{ $self->{'failed'}  };

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
    my ($self, @query_set) = @_;
    my %available;
    foreach my $name_version(@query_set){
	my ($module, $version) = @$name_version;
	my $query = File::Spec->catfile($self->location, 'query.py');	
	open(my $fh, '-|', "$query 'perl($module)' $version 2>/dev/null");
	my $loaded = <$fh>;
	while(my $found = <$fh>) {
	    chomp($found);
	    my ($name, $arch, $version, $source) = split(/\s/, $found);
	    $available{$name} = [ $name, $arch, $version, $source ];
	}
    }
    return \%available;
}

sub wanted_rpms {
    my $self = shift;
    my %wanted;

    open(my $csv, '<', $self->modules_file) or return \%wanted;
    while(my $line = <$csv>) {
	next if     $line =~ m/^#/; 
	next unless $line =~ /\w/;
	chomp($line);
	my ($perl_name, $version, $url, @extra) =
	    split(/,(?=(?:[^\"]*\"[^\"]*\")*(?![^\"]*\"))/, $line);

	(my $rpmname = $perl_name) =~ s/::/-/g;
	$rpmname     = "perl-$rpmname";

	$wanted{ $rpmname } = [ $rpmname, $perl_name, $version || 0, $url, @extra ];
    }

    return \%wanted;
}

sub run_cpan2rpm {
    my ($self, $module) = @_;

    my @cmd;
    push @cmd, File::Spec->catfile($self->location, 'cpan2rpm'), '--no-prfx';
    push @cmd, '--name', $module->[0];
    push @cmd, '--rpmbuild', File::Spec->catfile($self->location, 'cpan2rpmbuild');
    push @cmd, '--release', $self->release;

    if ($module->[2]){
	push @cmd, '--version', $module->[2];
    }

    if (@$module > 4) {
	my @extra = map { split(/ /, $_, 2) } @$module[4..$#$module];
	push @cmd, @extra;
    }

    if ($module->[3]){
	push @cmd, $module->[3];
    } else {
	push @cmd, $module->[1];
    }
    # push @cmd, '2>&1';
    warn "@cmd\n";
    if((system(@cmd) == 0)){
	push @{ $self->{'success'} }, $module->[0];
    } else {
	push @{ $self->{'failed'}  }, $module->[0];
	warn "Failed ", $module->[0], "\n";
    }
}

sub modules_file :lvalue { $_[0]->{'modules.file'}; }
sub location     :lvalue { $_[0]->{'location'};     }
sub release      :lvalue { $_[0]->{'release'};      }

sub getopt_spec {
    my $self = shift;
    $self->modules_file = 'modules.list';
    $self->location     = $FindBin::Bin;
    $self->release      = 'pfr';
    $self->{'success'}  = [];
    $self->{'failed'}   = [];
    return (
	'help'   => $self->usage,
	'file=s' => \$self->{'modules.file'},
	'build'  => \$self->{'run_build'},
	'rel=s'  => \$self->{'release'},
	);
}

sub usage { sub { exec 'perldoc', '-t', $0; }; }

exit ( __PACKAGE__->main(@ARGV) ) unless caller();

1;

=pod

=head1 NAME

rpm-builder.pl - build a lot of rpms

=head1 DESCRIPTION

=head1 SYNOPSIS

 ./rpm-builder.pl [options]

Where options and [defaults] are:

 -file <modules.file>  File with a list of modules in
 -build                Flag to enable actual building

=head1 MODULES.FILE

The modules file is a simple csv with the following columns

 Perl::Module::Name,version,http://.../Perl-Module-Name-v.tar.gz

For example

 Bio::DB::Sam,0,http://search.cpan.org/CPAN/authors/id/L/LD/LDS/Bio-SamTools-1.37.tar.gz

Only Perl::Module::Name is required, but please use all the commas. e.g.

 Class::DBI::Sweet,0.11,

=cut
