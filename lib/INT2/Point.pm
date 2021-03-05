use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::Point;
# ABSTRACT: thin wrapper for Geo::Point to ease reprojecting coordinate pairs


use Devel::StackTrace qw();
use Data::Dumper qw();

use Carp qw();
#use POSIX qw();

use Geo::LibProj::cs2cs 1.02;
use Geo::LibProj::FFI ();
our $proj = {};
my $trans = {};


sub wrap {
	my ($class, $geoPoint, $projnick, $point_projnick) = @_;
	# $projnick is a reference to the unique nick resolution hash
	my $instance = bless { point => $geoPoint, projnick => $projnick, myNick => $point_projnick }, $class;
	return $instance;
}


sub cs2cs_to {
	my ($self, $toNick) = @_;
	
	my $trans_key = "$self->{myNick} -> $toNick";
	
	unless ($trans->{$trans_key}) {
		my $from = $INT::Point::proj->{$self->{myNick}} or Carp::confess "nick '$self->{myNick}' unknown";
		my $to = $INT::Point::proj->{$toNick} or Carp::confess "nick '$toNick' unknown";
		$trans->{$trans_key} = Geo::LibProj::cs2cs->new($from => $to, {XS => 1});
	}
	
	return $trans->{$trans_key};
}


sub in {
	my ($self, $toNick) = @_;
	
	if ($toNick eq 'map' || $toNick eq 'geo') {
		$toNick = $self->{projnick}->{$toNick};
		Carp::confess 'illegal state: initialise map datums first!' unless $toNick;
	}
	
	my $cs2cs = $self->cs2cs_to($toNick);
	my $point = $cs2cs->transform($self->{point});
	return bless { point => $point, projnick => $self->{projnick}, myNick => $toNick }, __PACKAGE__;
}


sub x { shift->{point}->[0] }
sub y { shift->{point}->[1] }
sub long { shift->{point}->[0] }
sub lat  { shift->{point}->[1] }


1;
