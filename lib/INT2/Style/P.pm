use 5.012;
use warnings;

package INT2::Style::P;
# ABSTRACT: the border scale bar style "P" in INT2 (4th ed.) - 1:12501 to 1:30000


sub new {
	my ($class, $scalebar) = @_;
	my $self = bless {
		# lengths in metres
		label_interval => 1000,
		interval => 500,
		minor => 50,
		intermediate => 250,  # labelled minor
	}, $class;
	return $self;
}


1;
