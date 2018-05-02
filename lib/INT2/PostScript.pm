use 5.012;
use strict;
use warnings;
use diagnostics;

package INT2::PostScript;
# ABSTRACT: draw an INT2::Chart using PostScript


use Devel::StackTrace qw();
use Data::Dumper qw();

use Carp qw();
use POSIX qw();

use Geo::Point qw();
use Math::Round qw();

use INT2::Chart;

use constant FORMAT => '%.3f';


sub new {
	my $class = shift;
	my $instance = bless { @_ }, $class;
	$instance->init;
	return $instance;
}


sub init {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	my $psPtPerMillimetre = 72 / 25.4;
	$self->{paperWidthPt}  = $psPtPerMillimetre * $chart->{paperWidth};
	$self->{paperHeightPt} = $psPtPerMillimetre * $chart->{paperHeight};
	$self->{paperWidthHiResPt}  = sprintf(FORMAT, $self->{paperWidthPt});
	$self->{paperHeightHiResPt} = sprintf(FORMAT, $self->{paperHeightPt});
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	$self->{meridianFirst} = sprintf(FORMAT, $chart->{cornerSouthWest}->in('map')->x);
	$self->{meridianLast}  = sprintf(FORMAT, $chart->{cornerNorthEast}->in('map')->x);
	$self->{parallelFirst} = sprintf(FORMAT, $chart->{cornerSouthWest}->in('map')->y);
	$self->{parallelLast}  = sprintf(FORMAT, $chart->{cornerNorthEast}->in('map')->y);
	
	$self->{mapWidth} = $self->{meridianLast} - $self->{meridianFirst};
	$self->{mapHeight} = $self->{parallelLast} - $self->{parallelFirst};
	$self->{translationX} = ($chart->{paperWidth} - $self->{mapWidth}) / 2 + $chart->{offset}->[0];
	$self->{translationY} = ($chart->{paperHeight} - $self->{mapHeight}) / 2 + $chart->{offset}->[1];
	$self->{edgeTranslationY} = $chart->{suppressUpperEdge} ? $style->{outerEdgeWidth} / 2 * 80 / 100 : 0;  # 80/100: empirical value
	
	$self->{neatlineLocalSouth} = ($self->{translationY} + $self->{edgeTranslationY}) / $chart->{paperHeight};
	$self->{neatlineLocalNorth} = 1 - ($self->{translationY} - $self->{edgeTranslationY}) / $chart->{paperHeight};
	$self->{neatlineLocalWest}  = $self->{translationX} / $chart->{paperWidth};
	$self->{neatlineLocalEast}  = 1 - $self->{neatlineLocalWest};
	
	if ($self->{translationX} < 0 && $self->{translationY} < 0) {
		our @CARP_NOT;
		local @CARP_NOT = qw(INT2::Chart);
		Carp::carp sprintf "chart %s doesn't fit on page (%ix%i > %ix%i)", $chart->{chartNumber}, $self->{mapWidth}, $self->{mapHeight}, $chart->{paperWidth}, $chart->{paperHeight};
	}
	else {
		Carp::carp sprintf "chart %s size (%ix%i)", $chart->{chartNumber}, $self->{mapWidth}, $self->{mapHeight};
	}
}


sub chartAndStyle {
	my ($self) = @_;
	return ( $self->{chart}, $self->{chart}->{style} );
}


sub PostScriptStepThroughMinutes {
	my ($self, $options) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	# this algorithm assumes style E; for smaller scales, we probably need to use {minor}
	my @out = ();
#	push @out, Data::Dumper::Dumper($options);
	
	# step through entire range from begin to end, one minute at a time
	my $longitudeBegin = Math::Round::nhimult( $style->{minute}, $options->{begin} );
	my $longitudeEnd = Math::Round::nlowmult( $style->{minute}, $options->{end} );
	my $longitude = $longitudeBegin;
	while ($longitude <= $longitudeEnd) {
		my @line = ();
		
		# convert geographical to sheet coordinates
		my $point = $chart->newGeoPoint([$options->{latitude}->($longitude), $options->{longitude}->($longitude)], 'geo')->in('map');
		push @line, sprintf(FORMAT, $options->{mapCoordinate}->($point)), ' ';
		push @line, $options->{mapMath};
		
		# add a PostScript comment to make the output more human-understandable
		my $longitudeMinutes = ($longitude - POSIX::floor($longitude)) * 60;
		my $longitudeSeconds = ($longitudeMinutes - POSIX::floor($longitudeMinutes)) * 60;
		push @line, sprintf("  %% %0$options->{degreeDigits}d-%02d-%04.1f\n ",
				POSIX::floor($longitude), POSIX::floor($longitudeMinutes), $longitudeSeconds);
		
		# figure out which kind of step this is,
		# add PostScript code to deal with this step
		if ( defined $options->{PostScriptCode}->{degree} && defined $style->{degree}
				&& abs($longitude - Math::Round::nearest($style->{degree}, $longitude)) < $style->{epsilon} ) {
			push @line, $options->{PostScriptCode}->{degree}->(-1, $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{intermediate} && defined $style->{intermediate}
				&& abs($longitude - Math::Round::nearest($style->{intermediate}, $longitude)) < $style->{epsilon} ) {
			push @line, $options->{PostScriptCode}->{intermediate}->(-1, $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{minute} && defined $style->{minute} ) {
			push @line, $options->{PostScriptCode}->{minute}->(-1, $longitude);
		}
		else {
			next;
		}
		
		push @out, @line, "\n";
	}
	continue {
		# round longitude towards the floor to match longitudeEnd in loop condition
#warn($longitude) if $options->{test};
		$longitude = Math::Round::nlowmult($style->{minute}, $longitude + $style->{minute} + $style->{epsilon});
	}
#Carp::confess(Data::Dumper::Dumper($options)) if $options->{test};
	
	return @out;
}


sub PostScriptStepThroughSubdivisions {
	my ($self, $options) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	# this algorithm assumes style Fe; we probably need to use {minor}
	my @out = ();
#	push @out, Data::Dumper::Dumper($options) if $options->{test};
#	push @out, Data::Dumper::Dumper($style) if $options->{test};
	
	# step through entire range from begin to end, one minute at a time
	my $beginEndRoundTarget = defined $style->{minor} ? $style->{minor} : $style->{minute};
	my $longitudeBegin = Math::Round::nhimult( $beginEndRoundTarget, $options->{begin} - $style->{epsilon} );
	my $longitudeEnd = Math::Round::nlowmult( $beginEndRoundTarget, $options->{end} + $style->{epsilon} );
	my $longitude = $longitudeBegin;
	my @counters = (0, 0, 0, 0, 0);
	my $intermediateCounter = 0;
	my $minuteCounter = 0;
	my $minorCounter = 0;
	while ($longitude <= $longitudeEnd) {
		my @line = ();
		
		# convert geographical to sheet coordinates
		my $point = $chart->newGeoPoint([$options->{latitude}->($longitude), $options->{longitude}->($longitude)], 'geo')->in('map');
		push @line, sprintf(FORMAT, $options->{mapCoordinate}->($point)), ' ';
		push @line, $options->{mapMath};
		
		# add a PostScript comment to make the output more human-understandable
		my $longitudeMinutes = ($longitude - POSIX::floor($longitude)) * 60;
		my $longitudeSeconds = ($longitudeMinutes - POSIX::floor($longitudeMinutes)) * 60;
		push @line, sprintf("  %% %0$options->{degreeDigits}d-%02d-%04.1f\n ",
				POSIX::floor($longitude), POSIX::floor($longitudeMinutes), $longitudeSeconds);
		
		# figure out which kind of step this is,
		# add PostScript code to deal with this step
		if ( defined $options->{PostScriptCode}->{dicing} && defined $style->{dicing}
				&& abs($longitude - Math::Round::nearest($style->{dicing}, $longitude)) < $style->{epsilon} ) {
			$counters[4] += 1;  # dicing is counted separately
			push @line, $options->{PostScriptCode}->{dicing}->($counters[4], $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{degree} && defined $style->{degree}
				&& abs($longitude - Math::Round::nearest($style->{degree}, $longitude)) < $style->{epsilon} ) {
			$counters[0] += 1;
			$counters[1] += 1;
			$counters[2] += 1;
			$counters[3] += 1;
			push @line, $options->{PostScriptCode}->{degree}->($counters[0], $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{midDicing} && defined $style->{dicing}
				&& abs($longitude - Math::Round::nearest($style->{dicing}, $longitude)) < $style->{epsilon} ) {
			push @line, $options->{PostScriptCode}->{midDicing}->(-1, $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{intermediate} && defined $style->{intermediate}
				&& abs($longitude - Math::Round::nearest($style->{intermediate}, $longitude)) < $style->{epsilon} ) {
			$counters[1] += 1;
			$counters[2] += 1;
			$counters[3] += 1;
			push @line, $options->{PostScriptCode}->{intermediate}->($counters[1], $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{minute} && defined $style->{minute}
				&& abs($longitude - Math::Round::nearest($style->{minute}, $longitude)) < $style->{epsilon} ) {
			$counters[2] += 1;
			$counters[3] += 1;
			push @line, $options->{PostScriptCode}->{minute}->($counters[2], $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{minor} && defined $style->{minor} ) {
			$counters[3] += 1;
			push @line, $options->{PostScriptCode}->{minor}->($counters[3], $longitude);
		}
		elsif ( defined $options->{PostScriptCode}->{lateDicing} && defined $style->{dicing}
				&& abs($longitude - Math::Round::nearest($style->{dicing}, $longitude)) < $style->{epsilon} ) {
			push @line, $options->{PostScriptCode}->{lateDicing}->(-1, $longitude);
		}
		else {
			next;
		}
		
		if ($line[-1] ne 'pop') {
			push @out, @line, "\n";
		}
	}
	continue {
		# round longitude towards the floor to match longitudeEnd in loop condition
#warn($longitude) if $options->{test};
		$longitude = Math::Round::nlowmult($beginEndRoundTarget, $longitude + $beginEndRoundTarget + $style->{epsilon});
	}
#Carp::confess(Data::Dumper::Dumper($options)) if $options->{test};
	
	if ( defined $options->{PostScriptCode}->{final} ) {
		push @out, $options->{PostScriptCode}->{final}->(@counters), "\n";
	}
	
	return @out;
}


sub minimalFrame {
	my ($self, @frameContents) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	my $paperWidthPt  = $self->{paperWidthPt};
	my $paperHeightPt = $self->{paperHeightPt};
	my $paperWidthHiResPt  = $self->{paperWidthHiResPt};
	my $paperHeightHiResPt = $self->{paperHeightHiResPt};
	my $paperWidthIntPt  = POSIX::floor($paperWidthPt);
	my $paperHeightIntPt = POSIX::floor($paperHeightPt);
	
	my $chartNumber = $chart->{chartNumber};
	my $edgeSize = $style->{outerEdgeWidth};
	my $edgeTranslationY = $self->{edgeTranslationY};
	
	my $mapWidth = $self->{mapWidth};
	my $mapHeight = $self->{mapHeight};
	my $translationX = $self->{translationX};
	my $translationY = $self->{translationY};
	my $translationXPretty = sprintf(FORMAT, $translationX);
	my $translationYPretty = sprintf(FORMAT, $translationY + $edgeTranslationY);
#	print STDERR $translationYPretty;
	
	chomp (my $user = `whoami`);
	my $year = POSIX::strftime '%Y', localtime;
	
	my $version = $INT2::PostScript::VERSION // "DEV";
	my @postScript = <<"ENDPS";
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 $paperWidthIntPt $paperHeightIntPt
%%HiResBoundingBox: 0 0 $paperWidthHiResPt $paperHeightHiResPt
%%Title: Chart $chartNumber
%%Routing: PostScript Mercator grid
%%For: $user
%%Creator: INT2::PostScript $version, Arne Johannessen
%%CreationDate: $year
%%Copyright: Public Domain
%%Pages: 1
%%Orientation: Portrait
%%DocumentMedia: (A4) $paperWidthHiResPt $paperHeightHiResPt 0 () ()
%%+ (ISOA4) $paperWidthIntPt $paperHeightIntPt 0 () ()
%%LanguageLevel: 2
%%DocumentData: Clean7Bit
%%EndComments
%%BeginDefaults
%%PageMedia: (A4)
%%EndDefaults
%%BeginProlog

/mm { 72 mul 25.4 div } def

%%EndProlog
%%BeginSetup
[{ThisPage} << /TrimBox [ 0 0 $paperWidthHiResPt $paperHeightHiResPt ] >> /PUT pdfmark
<< /PageSize [$paperWidthHiResPt $paperHeightHiResPt] /Orientation 0 >> setpagedevice
50 dict begin
%%EndSetup
%%Page: (1) 1
%%BeginPageSetup
/pgsave save def
$translationXPretty mm $translationYPretty mm translate
%%EndPageSetup

ENDPS
	
	push @postScript, @frameContents;
	
	push @postScript, <<"ENDPS";
 
%%PageTrailer
pgsave restore
showpage
%%Trailer
end
%%EOF
ENDPS
	
	return @postScript;
}


sub frame {
	my ($self, @frameContents) = @_;
	
	return $self->minimalFrame($self->frameHead(), @frameContents);
}


sub frameHead {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	my $meridianFirst = $self->{meridianFirst};
	my $meridianLast  = $self->{meridianLast};
	my $parallelFirst = $self->{parallelFirst};
	my $parallelLast  = $self->{parallelLast};
	
	my $intermediateTickMarkLength = defined $style->{dicing} ? 3.5 : 3;
	my $minuteTickMarkLength = defined $style->{dicing} ? 2 : 1.5;
	my $borderWidth = $chart->{borderWidth};
	
	my @postScript = <<"ENDPS";

% ===== Constants, Units, Unit Conversions, Misc =====

/centerAlignment {
dup stringwidth pop
-2 div 0 rmoveto
} def

/rightAlignment {
dup stringwidth pop
neg 0 rmoveto
} def

/blackColor { 0 setgray } def
/magentaColor { 0 1 0 0 setcmykcolor } def
/greenColor { 1 0 1 0 setcmykcolor } def

% ===== Map Parameters =====

/setColor { blackColor } def

/graduation { 0.127 mm setlinewidth setColor 2 setlinecap } def
/neatline { graduation } def
/tickMarks { 0.127 mm setlinewidth setColor 0 setlinecap } def
/graticule { tickMarks } def
/mitredCorners { tickMarks } def
/dicing { 0.254 mm setlinewidth setColor 0 setlinecap } def
/borderStroke { 1 mm } def
/mapborder { borderStroke setlinewidth setColor 2 setlinecap } def

/borderWidth { $borderWidth mm } def
/degreeTickMark { 4 mm } def
/intermediateTickMark { $intermediateTickMarkLength mm } def
/minuteTickMark { $minuteTickMarkLength mm } def
/subdivisionTickMark { 0.8 mm } def


/meridianFirst { $meridianFirst } def
/meridianLast { $meridianLast } def
/parallelFirst { $parallelFirst } def
/parallelLast { $parallelLast } def


% ===== Projection Math =====

/longitude { meridianFirst sub mm } def
/latitude { parallelFirst sub mm } def

% PostScript code for the projection math used to be in this place in an
% earlier version of this framework. Projection math is now handled by the
% Perl script which generated this PS file.

ENDPS
	return @postScript;
}


sub GeoPDF {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	
	# calculate georegistation info
	# (see http://permalink.gmane.org/gmane.comp.gis.gdal.devel/20394)
	my @postScript;
	
	my $lat_0 = $chart->{trueScaleLatitude};
	my $neatlinePtWest = sprintf(FORMAT, $self->{neatlineLocalWest} * $self->{paperWidthHiResPt});
	my $neatlinePtEast = sprintf(FORMAT, $self->{neatlineLocalEast} * $self->{paperWidthHiResPt});
	my $neatlinePtSouth = sprintf(FORMAT, $self->{neatlineLocalSouth} * $self->{paperHeightHiResPt});
	my $neatlinePtNorth = sprintf(FORMAT, $self->{neatlineLocalNorth} * $self->{paperHeightHiResPt});
	my $meridianFirstUnscaled = $self->{meridianFirst} / $chart->{scale} / 1000;
	my $meridianLastUnscaled  = $self->{meridianLast} / $chart->{scale} / 1000;
	my $parallelFirstUnscaled = $self->{parallelFirst} / $chart->{scale} / 1000;
	my $parallelLastUnscaled  = $self->{parallelLast} / $chart->{scale} / 1000;
	# note: Acrobat *requires* parentheses
	# note: many of these parameters are "optional" according to the "best practices", but some apps require them
	push @postScript, <<"ENDPS";

% georegistration
[ {ThisPage} <<
  /LGIDict [ <<
    /Type /LGIDict
    /Version (2.1)
    /Projection <<
      /Type /Projection
      /Datum (WE)
      /ProjectionType (MC)
      /OriginLatitude ($lat_0)
      /CentralMeridian 0
      /FalseEasting 0
      /FalseNorthing 0
      /ScaleFactor 1
    >>
    /Registration [
      [ ($neatlinePtWest) ($neatlinePtSouth) ($meridianFirstUnscaled) ($parallelFirstUnscaled)]
      [ ($neatlinePtWest) ($neatlinePtNorth) ($meridianFirstUnscaled) ($parallelLastUnscaled)]
      [ ($neatlinePtEast) ($neatlinePtNorth) ($meridianLastUnscaled) ($parallelLastUnscaled)]
      [ ($neatlinePtEast) ($neatlinePtSouth) ($meridianLastUnscaled) ($parallelFirstUnscaled)]
    ]
    /Neatline [
      ($neatlinePtWest) ($neatlinePtSouth)
      ($neatlinePtWest) ($neatlinePtNorth)
      ($neatlinePtEast) ($neatlinePtNorth)
      ($neatlinePtEast) ($neatlinePtSouth)
    ]
  >> ]
>> /PUT pdfmark

ENDPS
	
	return @postScript;
}


sub GeoPDFAdobe {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	
	# calculate georegistation info
	# (see http://permalink.gmane.org/gmane.comp.gis.gdal.devel/20394)
	my @postScript;
	
	# BUG: this is the regular Adobe format, but it's not recognised by Acrobat for some reason
	# note: PDF Maps requires *no* parentheses, but leaving them out will cause precision degradation in the PostScript interpreter
	
	my $wkt = $self->{wkt};  # from INT2::Chart->PostScript
	my $neatlineSouth = $chart->{cornerSouthWest}->in('wgs')->y;
	my $neatlineNorth = $chart->{cornerNorthEast}->in('wgs')->y;
	my $neatlineWest  = $chart->{cornerSouthWest}->in('wgs')->x;
	my $neatlineEast  = $chart->{cornerNorthEast}->in('wgs')->x;
	my $neatlineLocalSouth = $self->{neatlineLocalSouth};
	my $neatlineLocalNorth = $self->{neatlineLocalNorth};
	my $neatlineLocalWest  = $self->{neatlineLocalWest};
	my $neatlineLocalEast  = $self->{neatlineLocalEast};
#       /Bounds [
#         ($neatlineLocalWest) ($neatlineLocalSouth)
#         ($neatlineLocalWest) ($neatlineLocalNorth)
#         ($neatlineLocalEast) ($neatlineLocalNorth)
#         ($neatlineLocalEast) ($neatlineLocalSouth)
#       ]
	# for some reason the coord order in GPTS is reversed wrt LPTS (?) <- PDF is x,y = right,up
	my $paperWidthHiResPt  = $self->{paperWidthHiResPt};
	my $paperHeightHiResPt = $self->{paperHeightHiResPt};
	push @postScript, <<"ENDPS";

% georegistration
[ {ThisPage} <<
  /VP [ <<
    /Type /Viewport
    /BBox [ 0 0 $paperWidthHiResPt $paperHeightHiResPt ]
    /Measure <<
      /Type /Measure
      /Subtype /GEO
      /GPTS [
        ($neatlineSouth) ($neatlineWest)
        ($neatlineNorth) ($neatlineWest)
        ($neatlineNorth) ($neatlineEast)
        ($neatlineSouth) ($neatlineEast)
      ]
      /LPTS [
        ($neatlineLocalWest) ($neatlineLocalSouth)
        ($neatlineLocalWest) ($neatlineLocalNorth)
        ($neatlineLocalEast) ($neatlineLocalNorth)
        ($neatlineLocalEast) ($neatlineLocalSouth)
      ]
      /GCS <<
        /Type /PROJCS
        /WKT ($wkt)
      >>
      /PDU [ /NM /SQKM /DEG ]
    >>
  >> ]
>> /PUT pdfmark

ENDPS
	
	return @postScript;
}


sub border {
	my ($self) = @_;
	
	return ($self->outerBorder, $self->neatline, $self->borderTicks, $self->chartNumber);
}


sub outerBorder {
	my ($self) = @_;
	
	my @postScript = <<"ENDPS";

% ===== Border =====

%%BeginObject: (Border)

newpath
0 borderWidth sub 0 borderWidth sub moveto
0 parallelLast latitude borderWidth 2 mul add rlineto
meridianLast longitude borderWidth 2 mul add 0 rlineto
meridianLast longitude borderWidth add 0 borderWidth sub lineto
0 borderWidth sub 0 borderWidth sub lineto
mapborder stroke

%%EndObject

ENDPS
	
	return @postScript;
}


sub neatline {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	my @postScript = <<"ENDPS";

% ===== Neatline and Graduation =====

%** neatlineDistance drawGraduationLine -
%** uses: parallelLast meridianLast latitude longitude
/drawGraduationLine {
/neatlineDistance exch def
neatlineDistance neg  neatlineDistance neg  moveto
neatlineDistance neg  parallelLast latitude neatlineDistance add  lineto
meridianLast longitude neatlineDistance add  parallelLast latitude neatlineDistance add  lineto
meridianLast longitude neatlineDistance add  neatlineDistance neg  lineto
neatlineDistance neg  neatlineDistance neg  lineto
} def

%** neatlineDistance drawGraduationLine -
%** uses: parallelLast meridianLast latitude longitude
/drawMitredCorners {
/neatlineDistance exch def
0 0 moveto
neatlineDistance neg neatlineDistance neg rlineto
0 parallelLast latitude moveto
neatlineDistance neg neatlineDistance rlineto
meridianLast longitude parallelLast latitude moveto
neatlineDistance neatlineDistance rlineto
meridianLast longitude 0 moveto
neatlineDistance neatlineDistance neg rlineto
} def

%%BeginObject: (Neatline)

newpath
0 drawGraduationLine
neatline stroke

%%EndObject


%%BeginObject: (Graduation Lines)
ENDPS
	if (defined $style->{dicing}) {
		push @postScript, <<"ENDPS";

newpath
minuteTickMark drawGraduationLine
subdivisionTickMark drawGraduationLine
graduation stroke
newpath
minuteTickMark drawMitredCorners
mitredCorners stroke

ENDPS
	}
	push @postScript, <<"ENDPS";
%%EndObject

ENDPS
	
	return @postScript;
}


sub borderTicks {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	my $cornerSouthWest = $chart->{cornerSouthWest}->in('geo');
	my $cornerNorthEast = $chart->{cornerNorthEast}->in('geo');
		
	my @postScript = <<"ENDPS";

% ===== Dicing =====

% %** dicingStart [map coordinates] dicingEnd [map coordinates] drawLongitudeDicing -
% %** uses: parallelLast latitude
/drawLongitudeDicing {
/dicingEnd exch def
/dicingStart exch def
dicingStart 1.4 mm neg moveto dicingEnd 1.4 mm neg lineto
dicingStart parallelLast latitude 1.4 mm add moveto dicingEnd parallelLast latitude 1.4 mm add lineto
} def

% %** dicingStart [map coordinates] dicingEnd [map coordinates] drawLatitudeDicing -
% %** uses: meridianLast longitude
/drawLatitudeDicing {
/dicingEnd exch def
/dicingStart exch def
1.4 mm neg dicingStart moveto 1.4 mm neg dicingEnd lineto
meridianLast longitude 1.4 mm add dicingStart moveto meridianLast longitude 1.4 mm add dicingEnd lineto
} def

%%BeginObject: (Dicing)
ENDPS
	if (defined $style->{dicing}) {
		push @postScript, <<"ENDPS";
	
newpath
1.4 mm neg
ENDPS
		
		push @postScript, $self->PostScriptStepThroughSubdivisions({
			begin => $cornerSouthWest->lat,
			end   => $cornerNorthEast->lat,
			latitude => sub { shift },
			longitude => sub { ($cornerSouthWest->long + $cornerNorthEast->long) / 2 },
			mapCoordinate => sub { shift->y },
			mapMath => 'latitude',
			PostScriptCode => {
				degree       => undef,
				intermediate => undef,
				minute       => undef,
				minor        => undef,
				dicing       => sub { $_[0] & 1 ? 'drawLatitudeDicing' : '' },
				final        => sub { $_[4] & 1 ? ' % |' : "parallelLast latitude 1.4 mm add\n drawLatitudeDicing" },
			},
			degreeDigits => 2,
		});
		
		push @postScript, <<"ENDPS";
%119821.232 latitude 10 mm add  % DUMMY TEST VALUE
%parallelLast latitude 1.4 mm add
%drawLatitudeDicing
dicing stroke

newpath
1.4 mm neg
ENDPS
		
		push @postScript, $self->PostScriptStepThroughSubdivisions({
			begin => $cornerSouthWest->long,
			end   => $cornerNorthEast->long,
			latitude => sub { $chart->{trueScaleLatitude} },
			longitude => sub { shift },
			mapCoordinate => sub { shift->x },
			mapMath => 'longitude',
			PostScriptCode => {
				degree       => undef,
				intermediate => undef,
				minute       => undef,
				minor        => undef,
				dicing       => sub { $_[0] & 1 ? 'drawLongitudeDicing' : '% |' },
				final        => sub { $_[4] & 1 ? ' % |' : "meridianLast longitude 1.4 mm add\n drawLongitudeDicing" },
			},
			degreeDigits => 2,
		});
		
		push @postScript, <<"ENDPS";
dicing stroke

ENDPS
	}
	push @postScript, <<"ENDPS";
%%EndObject


% ===== Tick Marks =====

%** latitude [map coordinates] length drawLatitudeTickMark -
%** uses: meridianLast longitude
/drawLatitudeTickMark {
dup 0 exch sub 2 index moveto
dup 0 rlineto
meridianLast longitude 0 rmoveto
0 rlineto
pop
} def

%** longitude [map coordinates] length drawLongitudeTickMark -
%** uses: parallelLast latitude
/drawLongitudeTickMark {
exch 0 2 index sub moveto
dup 0 exch rlineto
0 parallelLast latitude rmoveto
0 exch rlineto
} def

%** longitude [map coordinates] drawLongitudeDegreeTickMark -
%** uses: parallelLast latitude borderWidth intermediateTickMark
/drawLongitudeDegreeTickMark {
dup borderWidth neg moveto
0 degreeTickMark rlineto
parallelLast latitude borderWidth add moveto
0 degreeTickMark neg rlineto
} def

%%BeginObject: (TickMarks)

newpath
ENDPS
	
	# :BUG: We may need different code/values for lat and long (for 61 on A4 at least). -> lateDicing + midDicing are workaround
	push @postScript, $self->PostScriptStepThroughSubdivisions({
		begin => $cornerSouthWest->lat,
		end   => $cornerNorthEast->lat,
		latitude => sub { shift },
		longitude => sub { ($cornerSouthWest->long + $cornerNorthEast->long) / 2 },
		mapCoordinate => sub { shift->y },
		mapMath => 'latitude',
		PostScriptCode => {
			degree       => sub { '  borderWidth drawLatitudeTickMark' },
			intermediate => sub { '  intermediateTickMark drawLatitudeTickMark' },
			minute       => sub { 'minuteTickMark drawLatitudeTickMark' },
			minor        => sub { 'subdivisionTickMark drawLatitudeTickMark' },
			midDicing   => sub { '  intermediateTickMark drawLatitudeTickMark' },
		},
		degreeDigits => 2,
#			test => 1,
	});
#	return @postScript;
	
	push @postScript, <<"ENDPS";
tickMarks stroke

newpath
ENDPS
	
	push @postScript, $self->PostScriptStepThroughSubdivisions({
		begin => $cornerSouthWest->long,
		end   => $cornerNorthEast->long,
		latitude => sub { $chart->{trueScaleLatitude} },
		longitude => sub { shift },
		mapCoordinate => sub { shift->x },
		mapMath => 'longitude',
		PostScriptCode => {
			degree       => sub { "  dup degreeTickMark drawLongitudeTickMark\n  drawLongitudeDegreeTickMark" },
			intermediate => sub { '  intermediateTickMark drawLongitudeTickMark' },
			minute       => sub { 'minuteTickMark drawLongitudeTickMark' },
			minor        => sub { 'subdivisionTickMark drawLongitudeTickMark' },
#			lateDicing   => sub { 'minuteTickMark drawLongitudeTickMark' },
		},
		degreeDigits => 3,
	});
	
	push @postScript, <<"ENDPS";
tickMarks stroke

%%EndObject

ENDPS
	
	return @postScript;
}


sub chartNumber {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	my $chartNumber = $chart->{chartNumber};
	my $edgeSize = $style->{outerEdgeWidth};
	
	my @postScript = <<"ENDPS";

% ===== Chart Number =====

/chartNumberFontSize { $edgeSize mm } def
/chartNumberFont { /Helvetica findfont chartNumberFontSize scalefont setfont } def

%%BeginObject: (ChartNumber)

meridianLast longitude borderWidth add 0 borderWidth sub chartNumberFontSize sub moveto
0 chartNumberFontSize 20 div borderStroke sub 2 div  % try to adjust for "Schriftfleisch" (usually approx. 0) rmoveto
($chartNumber) chartNumberFont rightAlignment show

%%EndObject

ENDPS
	
	return @postScript;
}


sub graticule {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	my $cornerSouthWest = $chart->{cornerSouthWest}->in('geo');
	my $cornerNorthEast = $chart->{cornerNorthEast}->in('geo');
	
	my @postScript = <<"ENDPS";

% ===== Graticule =====

/drawParallel {
0 exch moveto
meridianLast longitude 0 rlineto
} def

/drawMeridian {
0 moveto
0 parallelLast latitude rlineto
} def

%%BeginObject: (Graticule)

newpath
ENDPS
	
	push @postScript, $self->PostScriptStepThroughMinutes({
		begin => $cornerSouthWest->lat + $style->{minute},
		end   => $cornerNorthEast->lat - $style->{minute},
		latitude => sub { shift },
		longitude => sub { ($cornerSouthWest->long + $cornerNorthEast->long) / 2 },
		mapCoordinate => sub { shift->y },
		mapMath => 'latitude',
		PostScriptCode => {
			degree       => sub { 'drawParallel'},
			intermediate => undef,
			minute       => undef,
		},
		degreeDigits => 2,
	});
	
	push @postScript, <<"ENDPS";
graticule stroke

newpath
ENDPS
	
	push @postScript, $self->PostScriptStepThroughMinutes({
		begin => $cornerSouthWest->long + $style->{minute},
		end   => $cornerNorthEast->long - $style->{minute},
		latitude => sub { $chart->{trueScaleLatitude} },
		longitude => sub { shift },
		mapCoordinate => sub { shift->x },
		mapMath => 'longitude',
		PostScriptCode => {
			degree       => sub { 'drawMeridian' },
			intermediate => undef,
			minute       => undef,
		},
		degreeDigits => 3,
	});
	
	push @postScript, <<"ENDPS";
graticule stroke

%%EndObject

ENDPS
	
	return @postScript;
}


sub graticuleLabels {
	my ($self) = @_;
	my ($chart, $style) = $self->chartAndStyle;
	
	if (! $chart->{cornerSouthWest} || ! $chart->{cornerNorthEast}) { die 'I need to know all map corner coordinates'; }
	my $cornerSouthWest = $chart->{cornerSouthWest}->in('geo');
	my $cornerNorthEast = $chart->{cornerNorthEast}->in('geo');
	
	# :HACK: provisional until Fe is properly implemented
	my $degreeUnitGlyph = "/degree";
	my $intermediateUnitGlyph = "/minute";
#	my $intermediateUnitGlyph = "/second";
	
	my @postScript = <<"ENDPS";

% ===== Labels =====

/degreeFontSize { 10 } def
/degreeFont { /Helvetica findfont degreeFontSize scalefont setfont } def
/intermediateFontSize { 8 } def
/intermediateFont { /Helvetica findfont intermediateFontSize scalefont setfont } def

/drawLatitudeDegreeLabelNoDicing {
exch moveto
0 degreeFontSize 3 div rmoveto
degreeFont centerAlignment show
} def

/drawLatitudeDegreeLabelsNoDicing {
exch 2 copy
borderWidth -2 div drawLatitudeDegreeLabelNoDicing
borderWidth 2 div meridianLast longitude add drawLatitudeDegreeLabelNoDicing
} def

/drawLatitudeIntermediateLabelNoDicing {
exch moveto
0 intermediateFontSize -3 div rmoveto
intermediateFont centerAlignment show
} def

/drawLatitudeIntermediateLabelsNoDicing {
exch 2 copy
borderWidth -2 div drawLatitudeIntermediateLabelNoDicing
borderWidth 2 div meridianLast longitude add drawLatitudeIntermediateLabelNoDicing
} def


/drawLongitudeDegreeLabelNoDicing {
moveto
intermediateFontSize neg degreeFontSize -3 div rmoveto
degreeFont rightAlignment show
} def

/drawLongitudeDegreeLabelsNoDicing {
exch 2 copy
borderWidth -2 div drawLongitudeDegreeLabelNoDicing
borderWidth 2 div parallelLast latitude add drawLongitudeDegreeLabelNoDicing
} def

/drawLongitudeIntermediateLabelNoDicing {
moveto
0 intermediateFontSize -3 div rmoveto
intermediateFont centerAlignment show
} def

/drawDoublePrime {
(") intermediateFont show
} def

/drawLongitudeIntermediateLabelsNoDicing {
exch 2 copy
borderWidth -2 div drawLongitudeIntermediateLabelNoDicing drawDoublePrime
borderWidth 2 div parallelLast latitude add drawLongitudeIntermediateLabelNoDicing drawDoublePrime
} def


/drawLatitudeDegreeLabel {
exch moveto
0 degreeFontSize 3 div rmoveto
degreeFont centerAlignment dup show
length 0 gt { $degreeUnitGlyph glyphshow } if
} def

/drawLatitudeDegreeLabels {
exch 2 copy
borderWidth -2 div .8 mm sub drawLatitudeDegreeLabel
borderWidth 2 div .8 mm add meridianLast longitude add drawLatitudeDegreeLabel
} def

/drawLatitudeIntermediateLabel {
exch moveto
0 intermediateFontSize -3 div rmoveto
intermediateFont centerAlignment show $intermediateUnitGlyph glyphshow
} def

/drawLatitudeIntermediateLabels {
exch 2 copy
borderWidth -2 div .8 mm sub drawLatitudeIntermediateLabel
borderWidth 2 div .8 mm add meridianLast longitude add drawLatitudeIntermediateLabel
} def


/drawLongitudeDegreeLabel {
moveto
intermediateFontSize neg degreeFontSize -3 div rmoveto
degreeFont rightAlignment dup show
length 0 gt { $degreeUnitGlyph glyphshow } if
} def

/drawLongitudeDegreeLabels {
exch 2 copy
borderWidth -2 div drawLongitudeDegreeLabel
borderWidth 2 div parallelLast latitude add drawLongitudeDegreeLabel
} def

/drawLongitudeIntermediateLabel {
moveto
0 intermediateFontSize -3 div rmoveto
intermediateFont centerAlignment show $intermediateUnitGlyph glyphshow
} def

/drawLongitudeIntermediateLabels {
exch 2 copy
borderWidth -2 div drawLongitudeIntermediateLabel
borderWidth 2 div parallelLast latitude add drawLongitudeIntermediateLabel
} def


%%BeginObject: (Labels)

ENDPS
	
	# We need to add $epsilon to prevent binary/decimal conversion errors from
	# dropping the values slighty below the whole number. Example:
	# 348.3 - 348 => 0.299999999999955 / *= 60 floor => 17 (incorrect)
	# 348.3 - 348 + epsilon => 0.300092592592547 / *= 60 floor => 18 (correct)
	my $epsilon = $style->{epsilon};
	
	my $getIntegerDegrees = sub { POSIX::floor(abs($_[1]) + $epsilon) };
	my $getIntegerMinutes = sub { POSIX::floor((abs($_[1]) - POSIX::floor(abs($_[1])) + $epsilon) * 60 + $epsilon) };
	my $getIntegerSeconds = sub { POSIX::floor((abs($_[1]) * 60 - POSIX::floor(abs($_[1]) * 60 + $epsilon)) * 60 + $epsilon) };
	
	push @postScript, $self->PostScriptStepThroughSubdivisions({
		begin => $cornerSouthWest->lat,
		end   => $cornerNorthEast->lat,
		latitude => sub { shift },
		longitude => sub { ($cornerSouthWest->long + $cornerNorthEast->long) / 2 },
		mapCoordinate => sub { shift->y },
		mapMath => 'latitude',
		PostScriptCode => $style->{labelsPostScriptLatitude},
		degreeDigits => 2,
	});
	
	push @postScript, <<"ENDPS";

ENDPS
	
	push @postScript, $self->PostScriptStepThroughSubdivisions({
		begin => $cornerSouthWest->long,
		end   => $cornerNorthEast->long,
		latitude => sub { $chart->{trueScaleLatitude} },
		longitude => sub { shift },
		mapCoordinate => sub { shift->x },
		mapMath => 'longitude',
		PostScriptCode => $style->{labelsPostScriptLongitude},
		degreeDigits => 3,
	});
	
	push @postScript, <<"ENDPS";

%%EndObject

ENDPS
	
	return @postScript;
}


#  PS math appears to be about 1.0023105005 larger than this <=> about 0.9976948256 factor to correct size of PS calculations (based on 62T). why?


1;
