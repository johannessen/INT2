use 5.012;
use warnings;

package INT2::Style::Q;
# ABSTRACT: the border scale bar style "Q" in INT2 (4th ed.) - 1:30001 to 1:50000


sub new {
	my ($class, $scalebar) = @_;
	my $self = bless {
		# lengths in metres
		label_interval => undef,  # every interval is labelled
		interval => 1000,
		minor => 100,
		intermediate => 500,  # labelled minor
	}, $class;
	return $self;
}


1;
