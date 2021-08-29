## 0.3.2 (August 29, 2021)
  - tritangulate: fixing 'finalize', as Integer zero won't comparte to Float zero
  - cotcube-level.rb: added :check_exceedance
  - helpers:member_to_human: added :daily param to distinguish stencils
  - tritangulate: added 'min_ratio' as param with lambda
  - eod_stencil: added #use to calculate current swap line value / dist;
  - tritangulate: added interval to be saved with the swap information.
  - helpers: moved puts_swaps to puts_swap, and added a :short switch for 1-liners per swap

## 0.3.1.1 (August 25, 2021)
  - trying to fix versioning mistake
  - Bump version to 0.3.2.1.
  - minor fixes correcting mistakes sneaked in during documentation rework
  - minor fix

## 0.3.2.1 (August 25, 2021)
  - minor fixes correcting mistakes sneaked in during documentation rework
  - minor fix

## 0.3.1 (August 24, 2021)
  - renaming triangulation to tritangulation
  - minor fixes in README and gemspec

## 0.3.0 (August 24, 2021)
  - removed tests, moving to cotcube-jobs
  - all: added documentation
  - triangulate: added continuous support and documentation
  - eod_stencil: added support for continuous futures
  - adapted tests to recent changes
  - cotcube-level: included intraday_stencil
  - intraday_stencil: added to repo
  - eod_stencil: fixing minor typo
  - triangulate: fixed indention
  - stencil: slight changes, incl rename to EODStencil
  - detect_slope: now returns all members, regardless of amount (i.e. check whether it is a valid swap will be done later)

## 0.2.0 (August 17, 2021)
  - cotcube-level: added new module_functions, added restrictive constants for intervals and swaptypes
  - adding new features to so-called 'test suite'
  - triangulate: added saving/caching, added rejection of base data older than abs_peak, utilized new output helpers, added analyzation lambda
  - helpers: added output helpers and save / load
  - fixed License definition
  - added current stuff to main module loader 'cotcube-level.rb'
  - added (copied from legacy swapseeker) and adapted module functions for swap detection (shearing, detect_slope, triangulate)
  - added (copied from legacy swapseeker) and adapted stencil model
  - added trivial testsuite for days, which contains loading of example data, stencil generation and slope detection

## 0.1.0 (May 07, 2021)
  - initial commit

