use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::Style::E_sexagesimal;
# ABSTRACT: the border style "E" (sexagesimal variant) in INT2 (3rd ed.) - larger than 1:30000


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
	
	# Es is the (E) template from INT2 in the 3rd edition sexagesimal version
	# (i. e. using seconds instead of tenths of minutes)
	# example: chart 62T
	
	my $epsilon = 1 / 60 / 60 / 3;
	my $getIntegerDegrees = sub { POSIX::floor(abs($_[1]) + $epsilon) };
	my $getIntegerMinutes = sub { POSIX::floor((abs($_[1]) - POSIX::floor(abs($_[1])) + $epsilon) * 60 + $epsilon) };
	my $getIntegerSeconds = sub { POSIX::floor((abs($_[1]) * 60 - POSIX::floor(abs($_[1]) * 60 + $epsilon)) * 60 + $epsilon) };
	$self->{degree} = .5 / 60,  # 0.5' intervals
	$self->{intermediate} = .1 / 60,  # 0.1' intervals
	$self->{minute} = 1 / 60 / 60,  # 1" intervals
	$self->{minor} = undef;  # not used
	$self->{epsilon} = $epsilon;
	$self->{labelsPostScriptLatitude} = {
		degree       => sub { "dup degreeFontSize add " . sprintf("(%i) drawLatitudeDegreeLabelsNoDicing\n ", &$getIntegerDegrees) . sprintf("dup (%i') drawLatitudeDegreeLabelsNoDicing\n ", &$getIntegerMinutes) . "intermediateFontSize 2 mul 3 div sub\n " . sprintf('(%02i") drawLatitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		intermediate => sub { sprintf('(%02i") drawLatitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		minute       => undef,
	};
	$self->{labelsPostScriptLongitude} = {
		degree       => sub { "dup " . sprintf("(%i %i') drawLongitudeDegreeLabelsNoDicing\n ", &$getIntegerDegrees, &$getIntegerMinutes) . sprintf('(%02i) drawLongitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		intermediate => sub { sprintf('(%02i) drawLongitudeIntermediateLabelsNoDicing', &$getIntegerSeconds) },
		minute       => undef,
	};
	
	# the width of the outer border (space for chart no. etc.)
	$self->{outerEdgeWidth} = 9;  # mm
}


1;
