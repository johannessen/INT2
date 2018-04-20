use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::PostScript::ShapeFile;
# ABSTRACT: draw ShapeFile spatial data on an INT2::Chart using PostScript


use INT2::Chart 0.50;

use Geo::ShapeFile::Point comp_includes_m => 0, comp_includes_z => 0;
use Geo::ShapeFile;



sub new {
	my ($class, %options) = @_;
	return bless {
		grid => $options{grid},
		bounds_xy => $options{bounds_xy},
		has_ps_code => 0,
	}, $class;
}


sub output_shape {
	my ($self, $name, $markovNick, $attr) = @_;
	
	my $shapefile = {
		name => $name,
		attr => $attr,
		markovNick => $markovNick,
	};
	
	my $grid = $self->{grid};
	my $bounds_xy = $self->{bounds_xy};
	
	my $postScriptSetMarkerCode = <<"ENDPS";

% ===== Markers =====

%%BeginObject: (Markers)

/strokeMarkers { 0.02 mm setlinewidth 0 setgray 2 setlinecap stroke } def
/markerFont { /Helvetica findfont 1 scalefont setfont } def
/showMarkerAnnotation { .05 mm .1 mm rmoveto markerFont show } def

/setMarker {
moveto
-.6 mm 0 rmoveto 1.2 mm 0 rlineto
-.6 mm -.6 mm rmoveto 0 1.2 mm rlineto
0 -.6 mm rmoveto
showMarkerAnnotation
} def


% ===== Marker Data =====

ENDPS
	
	
	my @marker = $self->{has_ps_code} ? () : ($postScriptSetMarkerCode);
	$self->{has_ps_code} = 1;
	push @marker, "% $shapefile->{name}.shp\n";
	push @marker, "newpath\n";
	my $file = Geo::ShapeFile->new($shapefile->{name});
	for(1 .. $file->shapes()) {
		my %db = $file->get_dbf_record($_);
		my $shape = $file->get_shp_record($_);
		my $parts = $shape->num_parts;
		if ($parts) {  # line(s)
			for(1 .. $parts) {
				my $part = $shape->get_part($_);
#				push @marker, "% OID $db{OID}\n";
				my $pen_down = 0;
				for(1 .. scalar @$part) {
					my $point = $part->[$_ - 1];
#					$point or next;
#					print "$point\n";
					my ($x, $y) = ($point->get_x, $point->get_y);
					if ($bounds_xy && ($x < $bounds_xy->[0] || $y < $bounds_xy->[1] || $x > $bounds_xy->[2] || $y > $bounds_xy->[3])) {
						$pen_down = 0;
						next;
					}
					my $mapPoint = $grid->newGeoPoint([$y, $x], $shapefile->{markovNick})->in('map');
#					push @marker, "% $mapPoint\n";
					push @marker, $mapPoint->x . " longitude " . $mapPoint->y . " latitude ";  #..
#					push @marker, $_ - 1 ? "lineto" : "moveto";
					push @marker, $pen_down ? "lineto" : "moveto";
					$pen_down = 1;
#					push @marker, "  % $_ / ", scalar @$part;
					push @marker, "\n";
#					use Data::Dumper;
#					my $a = Data::Dumper::Dumper $part;
#					$a =~ s/\n/| /g;
#					push @marker, "% $a\n";
				}
			}
		}
		else {  # point
			foreach my $point ($shape->points) {
				my ($x, $y) = ($point->get_x, $point->get_y);
				next if $bounds_xy && ($x < $bounds_xy->[0] || $y < $bounds_xy->[1] || $x > $bounds_xy->[2] || $y > $bounds_xy->[3]);
				my $mapPoint = $grid->newGeoPoint([$y, $x], $shapefile->{markovNick})->in('map');
#				push @marker, "% $mapPoint\n";
				push @marker, "(", $shapefile->{attr}->(\%db), ") ";
				push @marker, $mapPoint->x . " longitude " . $mapPoint->y . " latitude setMarker\n";  #..
#				use Data::Dumper;
#				print Data::Dumper::Dumper \%db;
			}
		}
	}
	push @marker, "strokeMarkers\n\n";
	
	return wantarray ? @marker : join '', @marker;
}



1;

__END__
