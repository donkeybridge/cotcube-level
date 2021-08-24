## Cotcube::Level

When naming this gem, I had in mind the German level a.k.a spirit level. But naming was not quite in the beginning
of the development process. All in the beginning was the wish to create an algorithm to automatically draw trend
lines. So for like 2 year I was whirling my head on how to put an algorithmic ruler on a chart and rotate it until
one or a set of trend lines are concise outpout. 

As most hard to accomplish things turn out to be much easier when you put them up side down, same happened to me in this
matter. I found rotating the ruler is too hard for, but instead transforming (shearing) the chart itself while keeping
the ruler at its _level_ is much more eligible.

The idea and the development of the algorithm had taken place within another Cotcube project named 'SwapSeeker'. At
some point the SwapSeeker has become too complex so I decided to decouple the Level and the Stencils as separate
functional unit, that can be used on arbitrary time series.

### The shear mapping

There is really no magic in it. The timeseries (or basically an interval of a timeseries) needs to be prepared to locate
in Cartesian Quadrant I with fitting x==0 to y==0, and then a binary search on shearing angles determines the resulting 
muiltitangent of which the origin ('now') as one point already is given. One limitation applies: Only shearing between
0 and 90 degrees is supported. 

The result contains 

- only the origin, if it is the absolute high (resp. low) within the provided interval of the time series. This happens
to happen if _deg -> 0_.
- the origin and one arbitrary point, the usual result.
- the origin and two or more points residing on the same level--what is the desired result showing mathematical accuracy where 
human eye cannot detect it in time. 

### Tritangulation

The 'tri' is about that to find an artificially supported slope (i.e. a swap) at least 3 points 
have to reside on it. It is leaned to triangulate, but instead of working with angles we are working with tangents here.

Shear mapping and slope detection might find a slope meeting the requirements. But in tritangulate, near misses are
considered and added as members. 

### The stencil

The shearing transformation is based on _x_ and _y_ values, where y obviously are the values of the series while _x_
refers to the time. It turned out a much bigger challenge to create an expedient mapping from DateTime to Integer,
where, as you foresee, 'now' should result in _x.zero?_. 

## Usage (pure template text)

TODO: Write usage instructions here

## Development (pure template text)

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/BSD-3-Clause).
