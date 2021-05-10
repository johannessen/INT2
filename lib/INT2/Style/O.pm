use 5.012;
use warnings;

package INT2::Style::O;
# ABSTRACT: the border scale bar style "O" in INT2 (4th ed.) - 1:12500 and larger


sub new {
	my ($class, $scalebar) = @_;
	my $self = bless {
		# lengths in metres
		label_interval => 500,
		interval => 100,
		minor => 20,
		intermediate => undef,  # no labelled minor
	}, $class;
	return $self;
}


1;
