use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::Style::Special;
# ABSTRACT: a 'special' border style for extremely large scales (e.g. 1:1500)


use Devel::StackTrace qw();
use Data::Dumper qw();

use Carp qw();
use POSIX qw();

#use Geo::Proj4 qw();
#use Geo::Proj qw();
#use Geo::Point qw();
#use Math::Round qw();

use constant FORMAT => '%.3f';


sub new {
	my ($class, $chart) = @_;
	my $instance = bless {}, $class;
	$instance->init($chart);
	return $instance;
}


sub init {
	my ($self, $chart) = @_;
	
# % Description of Tick Marks:
# % degree -- through line between border and neatline
# % intermediate -- labelled minute mark
# % minute -- default mark
# % minor -- subdivision of default mark
#   epsilon -- number significantly smaller than smallest of the numbers above
	
	# S is a 'special' template for extremely large scales, based on 'E'
	# (e. g. 1/1500) that is not based upon INT2
	# example: chart 12T
	
	my $epsilon = .2 / 60 / 60 / 3;
	my $getIntegerDegrees = sub { POSIX::floor(abs($_[1]) + $epsilon) };
	my $getIntegerMinutes = sub { POSIX::floor((abs($_[1]) - POSIX::floor(abs($_[1])) + $epsilon) * 60 + $epsilon) };
	my $getIntegerSeconds = sub { POSIX::floor((abs($_[1]) * 60 - POSIX::floor(abs($_[1]) * 60 + $epsilon)) * 60 + $epsilon) };
	$self->{degree} = .1 / 60;
	$self->{intermediate} = 1 / 60 / 60;
	$self->{minute} = 2 / 60 / 60 / 10;
	$self->{minor} = undef;
	$self->{epsilon} = $epsilon;
#	my $style = $self;
	$self->{chart} = $chart;
	$self->{labelsPostScriptLatitude} = {
		degree       => sub { "dup degreeFontSize add " . sprintf("(%i) drawLatitudeDegreeLabelsNoDicing\n ", &$getIntegerDegrees) . sprintf("dup (%i') drawLatitudeDegreeLabelsNoDicing\n ", &$getIntegerMinutes) . "intermediateFontSize 2 mul 3 div sub\n " . sprintf('(%02i") drawLatitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		intermediate => sub { return 'pop' if $self->skipLabel($_[1], $chart->{intermediateLatitudeLabels}); sprintf('(%02i") drawLatitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		minute       => undef,
	};
	$self->{labelsPostScriptLongitude} = {
		degree       => sub { "dup " . sprintf("(%i %i') drawLongitudeDegreeLabelsNoDicing\n ", &$getIntegerDegrees, &$getIntegerMinutes) . sprintf('(%02i) drawLongitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		intermediate => sub { return 'pop' if $self->skipLabel($_[1], $chart->{intermediateLongitudeLabels}); sprintf('(%02i) drawLongitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		minute       => undef,
	};
	
	# the width of the outer border (space for chart no. etc.)
	$self->{outerEdgeWidth} = 9;  # mm
}


sub skipLabel {
	my ($self, $coordinate, $coordinateExceptions) = @_;
	
	if ( ! $self->{chart}->{noIntermediateLabels} ) {
		return 0;
	}
	for my $labelCoordinate (@$coordinateExceptions) {
		if ( abs($coordinate - $labelCoordinate) < $self->{epsilon} ) {
			return 0;
		}
	}
	return 1;
}


1;

__END__
				&& abs($longitude - Math::Round::nearest($style->{minute}, $longitude)) < $style->{epsilon} ) {
	# special-case "intermediate" label texts
	$chart->{noIntermediateLabels} = $options->{noIntermediateLabels};
	$chart->{intermediateLatitudeLabels} = $options->{intermediateLatitudeLabels};
	$chart->{intermediateLongitudeLabels} = $options->{intermediateLongitudeLabels};
