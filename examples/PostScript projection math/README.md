PostScript Projection Math
==========================

Interpreters for the [PostScript](https://en.wikipedia.org/wiki/PostScript)
page description language are still widely available in high-end laser
printers. PostScript is a fully-fledged programming language that handles
any math thrown at it with ease. In theory, it should therefore be possible
to define PostScript procedures such that all coordinate calculations for
projected maps are handled by the PostScript interpreter rather than the
PostScript producer, enabling the cartographer to send unprojected geographic
coordinates directly to the printer using code like this:

```postscript
newpath
5.8276 deg longitude  60.0172 deg latitude  position moveto
5.8342 deg longitude  60.0210 deg latitude  position lineto
stroke
```

Or, if you prefer, to even use minutes and seconds rather than decimal degrees:

```postscript
newpath
5 deg 49 min 39 sec longitude  60 deg 1 min  2 sec latitude  position moveto
5 deg 50 min  3 sec longitude  60 deg 1 min 16 sec latitude  position lineto
stroke
```


In these PostScript code snippets, `longitude` and `latitude` are operators
that convert the given value from a geographic coordinate to a projected
coordinate using a simple Mercator projection in normal aspect. For example,
the PostScript interpreter might internally convert `5.8276 deg longitude` to
`237.45`, meaning 237.45 points from the paper’s left edge. The `position`
operator might be used for projections where the two coordinates are not
independent of each other; in Mercator, it is effectively a no-op.

Map and projection parameters can be defined like this:

```postscript
/meridianFirst { 5 deg 49.15 min longitude } def
/meridianLast { 5 deg 50.5 min longitude } def

/parallelFirst { 60 deg 0.35 min latitude } def
/parallelLast { 60 deg 1.80 min latitude } def

/scale { 1 10000 div } def
/trueScaleLatitude { 60 deg 0 min } def

% WGS 84 ellipsoid
/majorRadius { 6378137 m } def
/flattening { 1 298.257223563 div } def
```


The Mercator projection can be implemented in PostScript as follows.
The numerical operator identifiers in this code refer to the equations
(7-6), (7-7) and (7-8) in [Snyder’s 1987 paper on map
projections](https://pubs.er.usgs.gov/publication/pp1395)
(modified for another standard parallel as described on page 47).

```postscript
% ===== Constants, Units, Unit Conversions =====

/pi 3.141592653589793 def
/toRad { 180 div pi mul } def
/m {} def

/deg {} def
/min { 60 div add } def
/sec { 3600 div add } def

% ===== Projection Math =====

/longitude { 7-6 atMapScale meridianFirst 7-6 atMapScale sub } def
/latitude { 7-7 atMapScale parallelFirst 7-7 atMapScale sub } def
/position {} def

/7-6 {
toRad majorRadius mul
trueScaleLatitude 7-8 div
} def

/eccentricityTimesSineOfLatitude { sin eccentricitySquared sqrt mul } def

/7-7 {
dup 2 div 45 add tan exch
dup eccentricityTimesSineOfLatitude 1 exch sub exch
eccentricityTimesSineOfLatitude 1 add
div
eccentricitySquared sqrt 2 div
exp
mul ln majorRadius mul
trueScaleLatitude 7-8 div
} def

/7-8 {
dup sin2 eccentricitySquared mul 1 exch sub exch
cos
div
} def

% ===== Supplemental Math =====

/sin2 { dup sin exch sin mul } def
/tan { dup sin exch cos div } def
/eccentricitySquared { flattening 2 mul flattening dup mul sub } def
/atMapScale { scale mul 1000 mm mul } def
```


This approach seems to work reasonably well in practice at small scales.

However, because most PostScript interpreters only use single-precision
floating point numbers, unacceptable position errors are introduced at large
and even medium scales. While it might be possible to work around these issues
by adapting the mathematical formulas accordingly, doing so would likely negate
any advantages in terms of elegance this approach may provide.

Consequently, it seems more useful to use established projection libraries
such as Proj4 and only ever operate with projected coordinates in PostScript.
The INT2 Perl module does just that in all versions newer than 0.01.

Two hand-crafted example PostScript files with projection math are included
here for historical completeness.
