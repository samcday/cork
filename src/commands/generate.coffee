fs = require "fs"
{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	app.cork.generate cb