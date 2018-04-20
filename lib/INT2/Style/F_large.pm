use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::Style::F_large;
# ABSTRACT: the border style "F" in INT2 (4th ed.) - 1:30000 to 1:49999


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
	
	# Fe is the (F) template from INT2 in the "larger than 1:50000" special case
	# example: chart 61T
	
	my $epsilon = .1 / 60 / 3;
	my $getIntegerDegrees = sub { POSIX::floor(abs($_[1]) + $epsilon) };
	my $getIntegerMinutes = sub { POSIX::floor((abs($_[1]) - POSIX::floor(abs($_[1])) + $epsilon) * 60 + $epsilon) };
	my $getIntegerSeconds = sub { POSIX::floor((abs($_[1]) * 60 - POSIX::floor(abs($_[1]) * 60 + $epsilon)) * 60 + $epsilon) };
	$self->{degree} = 4 / 60;  # ??? intervals
	$self->{intermediate} = 2 / 60;  # 2' intervals
	$self->{minute} = .5 / 60;  # 0.5' intervals
	$self->{minor} = .1 / 60;  # 0.1' intervals
	$self->{dicing} = 1 / 60,  # 1' intervals
	$self->{epsilon} = $epsilon;
	$self->{labelsPostScriptLatitude} = {
		degree       => sub { "dup degreeFontSize add " . sprintf("() drawLatitudeDegreeLabels\n ", &$getIntegerDegrees) . sprintf("dup (%i) drawLatitudeDegreeLabels\n ", &$getIntegerDegrees) . "intermediateFontSize 2 mul 3 div sub\n " . sprintf('(%02i) drawLatitudeIntermediateLabels', &$getIntegerMinutes) },
#			intermediate => sub { if (! &$getIntegerSeconds) { sprintf('(%02i) drawLatitudeIntermediateLabels', &$getIntegerMinutes); } else { 'pop' } },
		minute       => undef,
		lateDicing   => sub { if (! &$getIntegerSeconds) { sprintf('(%02i) drawLatitudeIntermediateLabels', &$getIntegerMinutes) } else { 'pop' } },
	};
	$self->{labelsPostScriptLongitude} = {
		degree       => sub { if (0) { warn($_[1].' '.&$getIntegerMinutes); } return sprintf("(%i) drawLongitudeIntermediateLabels ", &$getIntegerMinutes) },
		intermediate => sub { if (! &$getIntegerSeconds) { sprintf('(%02i) drawLongitudeIntermediateLabels', &$getIntegerMinutes) } else { 'pop' } },
		minute       => undef,
	};
	
#	warn "style 'Fe' not implemented, using replacement based on 'E'";
	
	# the width of the outer border (space for chart no. etc.)
	$self->{outerEdgeWidth} = 9;  # mm
}


1;
