use 5.012;
use warnings;

package INT2::Style::R;
# ABSTRACT: the border scale bar style "R" in INT2 (4th ed.) - 1:50001 to 1:80000


sub new {
	my ($class, $scalebar) = @_;
	my $self = bless {
		# lengths in metres
		label_interval => 5000,
		interval => 1000,
		minor => 200,
		intermediate => undef,  # no labelled minor
	}, $class;
	return $self;
}


1;
