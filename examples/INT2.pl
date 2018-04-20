#! /usr/bin/env perl

use strict;
use warnings;

use INT2::Chart 0.53;
use INT2::PostScript::ShapeFile;



# use Geo::JSON::FeatureCollection;
# use Geo::JSON::Feature;
# use Geo::JSON::Polygon;
# 
# our @json_features;
# 
# sub writeJson {
# 	my $filename = shift;
# 	my $fcol = Geo::JSON::FeatureCollection->new({
# 		 features => \@json_features,
# 	});
# 	open(my $fh, '>', $filename) or die "Could not create file '$filename', $!";
# 	# Geo::JSON->codec->canonical(1)->pretty;
# 	my $json = $fcol->to_json;
# 	print $fh $json;
# 	close $fh;
# }



sub writeChart {
	my $options = shift;
	
#	push @{$options->{latitudeLabelExceptions}}, $options->{SW}->[0], $options->{NE}->[0];
#	push @{$options->{longitudeLabelExceptions}}, $options->{SW}->[1], $options->{NE}->[1];
	
	my $grid = INT2::Chart->new({
		datumProj4 => $INT2::Chart::wgs84Datum,
		trueScaleLatitude => 51,
		scale => $options->{scale},
		
		paperWidth => $options->{portrait} ? 210 : 297,  # mm A4
		paperHeight => $options->{portrait} ? 297 : 210,  # mm A4
		borderUpperEdge => 0,
		number => '' . $options->{No} . '',
		cornerSouthWest => $options->{SW},
		cornerNorthEast => $options->{NE},
		noIntermediateLabels => 1,
		intermediateLatitudeLabels => $options->{latitudeLabelExceptions},
		intermediateLongitudeLabels => $options->{longitudeLabelExceptions},
	});
	my $output = $grid->PostScript;
	
	my $marker = INT2::PostScript::ShapeFile->new(grid => $grid);
#	my $markovNick = 'shape1';
#	$grid->createProj4Nick($markovNick, '+proj=utm +zone=33 +datum=WGS84 +units=m +no_defs');
	
	my $filename = 'Netz ' . $options->{No} . '.ps';
	$filename =~ s(/)(\:);
	open(my $fh1, '>', $filename) or die "Could not create file '$filename', $!";
	print $fh1 $output->frame(
		$output->border,
#		$output->graticule,
		$output->graticuleLabels,
#		$marker->output_shape('shape/OSM-poly', 'wgs', undef), $marker->output_shape('shape/OSM-line', 'wgs', undef),
		$output->GeoPDF,
	);
	close $fh1;
	`ps2pdf "$filename"`;
#	`rm "$filename"`;
	
	
	$filename = 'georef' . $options->{No} . '.eps';
	$filename =~ s(/)(\:);
	open(my $fh2, '>', $filename) or die "Could not create file '$filename', $!";
	print $fh2 $output->minimalFrame(
		$output->GeoPDF,
	);
	close $fh2;
	
	
	# :BUG: assumes WGS84
# 	push @json_features, Geo::JSON::Feature->new({
# 		geometry => Geo::JSON::Polygon->new({ coordinates => [[
# 			[$options->{SW}->[1], $options->{SW}->[0]],
# 			[$options->{NE}->[1], $options->{SW}->[0]],
# 			[$options->{NE}->[1], $options->{NE}->[0]],
# 			[$options->{SW}->[1], $options->{NE}->[0]],
# 			[$options->{SW}->[1], $options->{SW}->[0]],
# 		]]}),
# 		properties => {
# 			chart => $grid->{chartNumber},
# 		},
# 	});
}



# writeChart {
# 	No => '17',
# 	scale => 1 / 10_000,
# 	portrait => 0,
# 	SW => [ 51 +  4/60 +   6/3600,  7 + 33/60 +  6/3600 ],
# 	NE => [ 51 +  5/60 +   0/3600,  7 + 35/60 + 15/3600 ],
# #	latitudeLabelExceptions => [ 60 +  0/60 + 31.0/3600 ],
# #	longitudeLabelExceptions => [ 5 + 49/60 +  1/3600,  5 + 49/60 + 10/3600 ],
# };

# writeChart {
# 	No => '17',
# 	scale => 1 / 10_000,
# 	portrait => 0,
# 	SW => [ 51 +  4/60 +  12/3600,  7 + 33/60 +  6/3600 ],
# 	NE => [ 51 +  5/60 +   6/3600,  7 + 35/60 + 15/3600 ],
# #	latitudeLabelExceptions => [ 60 +  0/60 + 31.0/3600 ],
# #	longitudeLabelExceptions => [ 5 + 49/60 +  1/3600,  5 + 49/60 + 10/3600 ],
# };

writeChart {
	No => '17',
	scale => 1 / 10_000,
	portrait => 0,
	SW => [ 51 +  4/60 +  15/3600,  7 + 33/60 +  6/3600 ],
	NE => [ 51 +  5/60 +   3/3600,  7 + 35/60 + 12/3600 ],
#	latitudeLabelExceptions => [ 60 +  0/60 + 31.0/3600 ],
#	longitudeLabelExceptions => [ 5 + 49/60 +  1/3600,  5 + 49/60 + 10/3600 ],
};

# writeChart {
# 	No => '17 @8000',
# 	scale => 1 / 8_000,
# 	portrait => 0,
# 	SW => [ 51 +  4/60 +  15/3600,  7 + 33/60 +  9/3600 ],
# 	NE => [ 51 +  4/60 +  57/3600,  7 + 34/60 + 51/3600 ],
# #	latitudeLabelExceptions => [ 60 +  0/60 + 31.0/3600 ],
# #	longitudeLabelExceptions => [ 5 + 49/60 +  1/3600,  5 + 49/60 + 10/3600 ],
# };


# writeJson 'neatline.geojson';



exit 0;
