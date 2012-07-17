module.exports = util = require "util"

util.safeJSON = 
	# Parses JSON safely. Assumes the caller has a relevant callback that can be
	# notified of the failures gracefully.
	parse: (str, cb) ->
		try
			return JSON.parse str
		catch error
			cb new Error "Error parsing JSON" if cb
			return null