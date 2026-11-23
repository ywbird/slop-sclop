-- sclog entry point: the `sclog` script runs this with `sclop -l`.
-- main returns an exit code; quit ends the event loop with it.
sclop.quit(require('sclop.log').main{ ... })
