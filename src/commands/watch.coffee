fs = require "fs"
async = require "async"
{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	app.cork.generate (err) ->
		return cb err if err
		async.parallel [
			(cb) -> app.cork.server cb
			(cb) -> app.cork.watch cb
		], cb