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

use Geo::Point qw();


sub wrap {
	my ($class, $geoPoint, $projnick) = @_;
	my $instance = bless { point => $geoPoint, projnick => $projnick }, $class;
	return $instance;
}


sub in {
	my ($self, $toNick) = @_;
	
	if ($toNick eq 'map' || $toNick eq 'geo') {
		$toNick = $self->{projnick}->{$toNick};
		Carp::confess 'illegal state: initialise map datums first!' unless $toNick;
	}
	
	return $self->{point}->in($toNick);
}


1;
