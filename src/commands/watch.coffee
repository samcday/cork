fs = require "fs"
{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	app.cork.generate (err) ->
		return cb err if err
		console.log "yeah boi!"
		app.cork.listen 4000, ->
			console.log "listening."