use 5.012;
use warnings;

package INT2::Scalebar;
# ABSTRACT: IHO INT2 scale bar generator


use INT2::Style::O;
use INT2::Style::P;
use INT2::Style::Q;
use INT2::Style::R;

use SVG;


my $HEIGHT = 1.0;  # mm
my $LINE_WEIGHT = '0.12mm';  # optimised for AI CS6; might be a bug
my %TEXT_STYLE = (
	'font-family' => 'Helvetica',
	'font-size' => '0.75mm',  # optimised for AI CS6; might be a bug
);


sub new {
	my ($class, $options) = @_;
	my $self = bless {
		svg_options => {
			-nocredits => 1,
		},
	}, $class;
	return $self->init($options);
}


sub init {
	my ($self, $options) = @_;
	
	$self->{scale} = $options->{scale};
	$self->{style} = $options->{style};
	$self->{max_length} = $options->{max_length};
	
	$self->{svg_options} = $options->{svg_options} if $options->{svg_options};
	$self->{svg_height} = $options->{svg_height};
	$self->{line_weight} = $options->{line_weight};
	$self->{height} = $options->{height};
	$self->{tick_height} = $options->{tick_height};
	$self->{text_style} = $options->{text_style};
	
	return $self;
}


sub scale {
	my ($self) = @_;
	
	# normalise scale
	my $scale = $self->{scale};
	die "required option 'scale' missing" unless $scale;
	$scale = abs $scale;
	$scale = 1 / $scale if $scale > 1;
	return $scale;
}


sub style {
	my ($self) = @_;
	
	if (! $self->{style}) {
		my $scale = $self->scale;
		$self->{style} = 'INT2::Style::R';  # officially only for scale <= 1 / 80_000
		$self->{style} = 'INT2::Style::Q' if $scale > 1 / 50_001;
		$self->{style} = 'INT2::Style::P' if $scale > 1 / 30_001;
		$self->{style} = 'INT2::Style::O' if $scale > 1 / 12_501;
	}
	
	return "$self->{style}"->new($self);
}


sub calc {
	my ($self) = @_;
	
	my $style = $self->style;
	my $scale = $self->scale * 1000;  # calculation is for mm
	
	my $interval       = $scale * $style->{interval};
	my $label_interval = $scale * ($style->{label_interval} || $style->{interval});
	my $minor          = $scale * $style->{minor};
	my $intermediate   = $scale * ($style->{intermediate} || 0);
	
	my $length = $self->{max_length} || 450;  # mm (B-221.1)
	my $intervals = int( ($length - $interval) / $label_interval ) * $label_interval / $interval;
	my $minors = $style->{interval} / $style->{minor};
	
	my @marks;
	my $epsilon = $self->{line_weight} || $LINE_WEIGHT;
	{ no warnings 'numeric'; $epsilon += 0; }
	
	# minor (backward)
	if ($minor) {
		for my $i ( reverse 1 .. $minors ) {
			my $x = $i * $minor;
			my $label = 0;
			$label = abs($x / $intermediate) - int( abs($x / $intermediate) + $epsilon * .5 ) <= $epsilon if $intermediate;
			push @marks, {
				X => -$x,
				distance => $i * $style->{minor},
				label => $label,
			};
		}
	}
	
	# forward
	for my $i ( 0 .. $intervals ) {
		my $x = $i * $interval;
		push @marks, {
			X => $x,
			distance => $i * $style->{interval},
			label => abs($x / $label_interval) - int( abs($x / $label_interval) + $epsilon * .5 ) <= $epsilon,
		};
	}
	
	$marks[0]->{end} = 1;
	$marks[0]->{label} = 1;
	$marks[$#marks]->{end} = 1;
	$marks[$#marks]->{label} = 1;
	
	return $self->{marks} = \@marks;
}


sub svg {
	my ($self) = @_;
	
	my $marks = $self->calc;
	
	my $last = $marks->[@$marks - 1];
	my $first = $marks->[0];
	my $width = $last->{X} - $first->{X};
	
	my $svg_width = int($width + 65);
	my $svg_height = $self->{svg_height} || 30;
	my $svg = SVG->new(
		%{$self->{svg_options}},
		width => "${svg_width}mm",
		height => "${svg_height}mm",
		viewBox => "0 0 $svg_width $svg_height",
	);
	my $translate_x = abs($first->{X}) + 30;
	my $left = $svg->group(
		id => 'left_border',
		transform => "translate($translate_x,10)",
	);
	my $right = $svg->group(
		id => 'right_border',
		transform => "translate($translate_x,20)",
	);
	
	my $height = $self->{height} || $HEIGHT;
	my $tick_height = $self->{tick_height} // $height;
	my $line_width = $self->{line_weight} // $LINE_WEIGHT;
	my $tick_y = -$height - $tick_height;
	my $text_y = -$height - 2 * $tick_height;
	my $line_style = {
		stroke => 'black',
		fill => 'none',
		'stroke-width' => "$line_width",
	};
	my $text_style = $self->{text_style} || \%TEXT_STYLE;
	
	my %bar_data = (
		'x' => $marks->[0]{X},
		'y' => -$height,
		width => $width,
		height => $height,
		style => $line_style,
	);
	$left->rect(%bar_data);
	$right->rect(%bar_data);
	
	for my $mark (@$marks) {
		my $svg_mark = sub {
			my ($ele, $x) = @_;
			$ele->line(
				x1 => $x,
				y1 => $mark->{end} ? -$height : 0,
				x2 => $x,
				y2 => $mark->{label} ? $tick_y : -$height,
				style => $line_style,
			);
			if ($mark->{label}) {
				my %text_attr = (
					'x'  => $x,
					'y'  => $text_y,
					style => $text_style,
					style => { %$text_style, 'text-anchor' => 'middle' },
				);
				$text_attr{fill} = 'red' if $mark->{end};
				$ele->text(%text_attr)->cdata($mark->{distance});
			}
		};
		
		$svg_mark->($left, $mark->{X});
		$svg_mark->($right, $last->{X} + $first->{X} - $mark->{X});
	}
	
	$left->text(
		'x'  => $last->{X} + 6,
		'y'  => $text_y,
		style => { %$text_style, 'text-anchor' => 'start' },
	)->cdata("$last->{distance} METRES");
	$right->text(
		'x'  => $last->{X} + 6,
		'y'  => $text_y,
		style => { %$text_style, 'text-anchor' => 'start' },
	)->cdata("$first->{distance} METRES");
	$left->text(
		'x'  => $first->{X} - 6,
		'y'  => $text_y,
		style => { %$text_style, 'text-anchor' => 'end' },
	)->cdata("METRES $first->{distance}");
	$right->text(
		'x'  => $first->{X} - 6,
		'y'  => $text_y,
		style => { %$text_style, 'text-anchor' => 'end' },
	)->cdata("METRES $last->{distance}");
	
	return $svg;
}


1;

# TODO: automatically determine scale and max_length from an INT2::Chart instance
