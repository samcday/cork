{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	app.prompt.get "Wzzicked!", (err, result) ->
		console.log result
		cb()