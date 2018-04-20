use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::Chart;
# ABSTRACT: a single map sheet with IHO INT2 style borders


use Devel::StackTrace qw();
use Data::Dumper qw();

use Carp qw();
use POSIX qw();

use Geo::Proj4 qw();  # this module is not mentioned in the code; is there a reason for this?
use Geo::Proj qw();
use Geo::Point qw();

use INT2::Point;
use INT2::PostScript;


our $wgs84Datum = '+ellps=WGS84 +datum=WGS84';
our $ngo48Datum = '+a=6377492.0176 +rf=299.15281285 +towgs84=278.3,93,474.5,7.889,.05,-6.61,6.21';
our $ngo48DatumOslo = "$ngo48Datum +pm=oslo";
our $ed50Datum = '+ellps=intl +towgs84=-87,-95,-120';
our $dhdn95Datum    = '+ellps=bessel +towgs84=582,105,414,1.04,.35,-3.08,8.3';         # DE old
our $dhdn77Datum    = '+ellps=bessel +towgs84=566.1,116.3,390.1,1.11,.24,-3.76,12.6';  # NRW
our $dhdn77DatumVII = '+ellps=bessel +towgs84=573.6,108,394.2,1.31,.19,-3.05,11.5';    # NRW, Waldbroel = best for Brucher! ***
our $dhdn01DatumM   = '+ellps=bessel +towgs84=584.8,67,400.3,.105,.013,-2.378,10.29';  # DE new, Mitte = reasonable for Brucher
our $dhdn01Datum    = '+ellps=bessel +towgs84=598.1,73.7,418.2,.202,.045,-2.455,6.7';  # DE new
# also very good for Brucher: BeTA2007 grid transformation
# our $dhdn07Datum    = '+ellps=bessel +nadgrids=BETA2007.gsb';  # DE BeTA2007; use full absolute pathname!
# difference between dhdn77DatumVII/dhdn01DatumM/dhdn07Datum

our $nextProj4NickId = 1;


sub new {
	my ($class, $options) = @_;
	my $instance = bless {}, $class;
	return $instance->init($options);
}


sub init {
	my ($self, $options) = @_;
	
	# ensure we have a usable normalised scale
	my $scale = $options->{scale};
	if (! $scale) { die 'I need to know the map scale'; }
	$scale = abs $scale;
	if ($scale > 1) { $scale = 1 / $scale; }
	$self->{scale} = $scale;
	
	# set INT2 style
	my $style = $options->{style};
	# can be a Style object, a Style class name or nothing
	if (! ref $style) {
		# if not given explicitly, infer from reference or use defaults
		$style = $self->loadStyle( $style );
	}
	$self->{style} = $style;
	
	# init map datum/CRS
	$self->{trueScaleLatitude} = $options->{trueScaleLatitude} || 0;
	$self->initMapDatum($options);
	
	# corner coordinates
	$self->{cornerSouthWest} = $self->newGeoPoint($options->{cornerSouthWest}) if $options->{cornerSouthWest};
	$self->{cornerNorthEast} = $self->newGeoPoint($options->{cornerNorthEast}) if $options->{cornerNorthEast};
	
	# use A0 measures by default (millimetres)
	$self->{paperWidth} = $options->{paperWidth} || 1189;
	$self->{paperHeight} = $options->{paperHeight} || 841;
	
	# outer borders
	$self->{chartNumber} = $options->{number} || '';
	$self->{suppressUpperEdge} = ! $options->{borderUpperEdge};
	
	# special-case "intermediate" label texts
	$self->{noIntermediateLabels} = $options->{noIntermediateLabels};
	$self->{intermediateLatitudeLabels} = $options->{intermediateLatitudeLabels};
	$self->{intermediateLongitudeLabels} = $options->{intermediateLongitudeLabels};
	
	return $self;
}


sub initMapDatum {
	my ($self, $options) = @_;
	
	my $datumProj4 = $wgs84Datum;
	$datumProj4 = $options->{datumProj4} if defined $options->{datumProj4};
	
	my $crsProj4 = "+proj=latlon $datumProj4 +no_defs";
	my $mapProj4 = "+proj=merc $datumProj4 #lat_ts #to_meter +no_defs";  # createProj4Nick replacement strings
	$crsProj4 = $options->{coordRefSystem} if $options->{coordRefSystem};
	$mapProj4 = $options->{mapProjection} if $options->{mapProjection};
	
	$self->{projnick} = {};
	$self->createProj4Nick('geo', $crsProj4);
	$self->createProj4Nick('map', $mapProj4);
	$self->createProj4Nick('wgs', "+proj=latlon $wgs84Datum +no_defs");
	
#	warn Data::Dumper::Dumper($self->{projnick});
}


sub createProj4Nick {
	my ($self, $nick, $proj4) = @_;
	
	# $proj4 may be a proj4 definition string or a Geo::Proj4 instance
	if (! ref $proj4) {
		# the definition string may contain placeholders that need to be replaced
		if (! ref $self && $proj4 =~ /#/) { Carp::croak 'createProj4Nick with replacement strings can\'t be called as class method because the replacements are based on instance data'; }
		$proj4 =~ s(#lat_ts)('+lat_ts=' . $self->{trueScaleLatitude})e;
		$proj4 =~ s(#to_meter)('+to_meter=' . .001 / $self->{scale})e;  # map coordinates in millimetres at map scale
	}
	
	warn "$proj4" if $nick eq 'map';
	
	my $markovNick = $nick;
	if ($nick eq 'map' || $nick eq 'geo') {
		$markovNick .= $nextProj4NickId++;
		$self->{projnick}->{$nick} = $markovNick;
	}
	
	Geo::Proj->new(nick => $markovNick, proj4 => $proj4);
	# nick and proj are automatically stored in a cache inside Geo::Proj
	# known mis-feature (AKA 'bug') in Geo::Proj: that cache is immutable
}


sub newGeoPoint {
	my ($self, $point, $projNick) = @_;
	$projNick ||= 'geo';
	
	if ($projNick eq 'map' || $projNick eq 'geo') {
		$projNick = $self->{projnick}->{$projNick} || die;
	}
	
	# $point may be a definition string, a lat/lon coordinate array or a Geo::Point instance
	if (! ref $point) {
#	warn Data::Dumper::Dumper($self->{projnick});
		Carp::confess 'illegal state: initialise map datums first!' unless $self->{projnick};
		$point = INT2::Point->wrap( Geo::Point->fromString($point, $projNick), $self->{projnick} );
	}
	elsif (ref $point eq 'ARRAY') {
#	warn Data::Dumper::Dumper($self->{projnick});
		Carp::confess 'illegal state: initialise map datums first!' unless $self->{projnick};
		$point = INT2::Point->wrap( Geo::Point->latlong(@$point, $projNick), $self->{projnick} );
	}
	
	return $point;
}


sub loadStyle {
	my ($self, $ref) = @_;
	$ref ||= $self->styleRefFromScale($self->{scale});
	
# % Description of Tick Marks:
# % degree -- through line between border and neatline
# % intermediate -- labelled minute mark
# % minute -- default mark
# % minor -- subdivision of default mark
#   epsilon -- number significantly smaller than smallest of the numbers above
	
	my $style;
	eval "require $ref";  # NB: double quote so that module name is bareword and we don't need to muck around with the path/filename
	if ($@) {
		warn $@;
		die "style '$ref' unknown or not implemented";
	}
	eval '$style = $ref->new($self)';  # NB: single quote for assignment to variable
	if ($@) {
		die $@;
	}
	
	return $style;
}


sub styleRefFromScale {
	my ($self, $scale) = @_;
	$scale = $scale || $self->{scale};
	
	# normalise scale
	if (! $scale) { die "required scalar attribute 'scale' missing"; }
	$scale = abs $scale;
	if ($scale > 1) { $scale = 1 / $scale; }
	
	# refer to INT2's graduation table (3rd ed.)
	return 'INT2::Style::Special'       if $scale > 1 /     2_250;  # 'special' graduation for very large scales
	return 'INT2::Style::E_sexagesimal' if $scale > 1 /    30_000;  # we use the sexagesimal version by default
	return 'INT2::Style::F_large'       if $scale > 1 /    50_000;  # special intermediate interval in footnote
	return 'INT2::Style::F'             if $scale > 1 /   100_000;
	return 'INT2::Style::G'             if $scale > 1 /   200_000;
	return 'INT2::Style::H'             if $scale > 1 /   500_000;
	return 'INT2::Style::J'             if $scale > 1 / 1_500_000;
	return 'INT2::Style::K'             if $scale > 1 / 2_250_000;
	return 'INT2::Style::L'             if $scale > 1 / 4_750_000;
	return 'INT2::Style::M';  # officially only for scale exactly == 1 / 10_000_000
}


sub PostScript {
	my ($self) = @_;
	
	# WKT of map projection required for GeoPDF georegistation info
	# open question: why use a special proj4 string instead of the normal one for the map? does GeoPDF perhaps not support non-WGS datums?
	# known bug: for non-WGS datums, lat_ts (and by inference the map's scale) will be slightly off in the WKT. but does that even matter, or is it just about the ellipsoid?
	my $mapWgs = "+proj=merc $INT2::Chart::wgs84Datum +lat_ts=" . $self->{trueScaleLatitude} . " +lon_0=0 +x_0=0 +y_0=0 +units=m +no_defs";
	my $wkt = `gdalsrsinfo -o wkt_esri '$mapWgs'`;
	chomp $wkt;
	
	return INT2::PostScript->new(
		chart => $self,
		wkt => $wkt,
	);
}


1;

__END__

=pod

=head1 SEE ALSO

L<https://www.iho.int/iho_pubs/IHO_Download.htm#Standards>

=cut
