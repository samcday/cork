{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	# console.log app.cork.npm
	# return cb()
	app.cork.npm.install "cork-content-markdown", ->
		console.log "all done!"
