cli = require "./cli"
Cork = require "./cork"

exports.run = () ->
	if root
		cli.cork = cork = (new Cork module.parent) if root
		Object.defineProperty cork, "log", get: -> cli.log
		cli.cork.init (err) ->
			return console.error err if err # TODO:
			cli.start (err) ->
				console.log "done."
