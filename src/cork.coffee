glob = require "glob"
fs = require "fs"
path = require "path"
async = require "async"

validAnnexTypes = ["content", "blog"]

regex = 
	annexType: /^(.*?)\.annex$/

module.exports = class Cork
	constructor: (@root) ->
		@annexes = []
	init: (cb) ->
		async.series [
			@_loadConfig
			@_discoverAnnexes
		], (err) ->
			cb err
	# Load the main configuration from cork.json
	_loadConfig: (cb) =>
		fs.readFile (path.join @root, "cork.json"), "utf8", (err, data) =>
			return cb err if err?
			@config = JSON.parse data
			console.log "lol", @config
			cb()
	# Discovers all modules inside cork app.
	_discoverAnnexes: (cb) =>
		self = @
		glob "#{@root}/**/*.annex", (err, files) ->
			processAnnex = (annexPath, cb) ->
				annexFile = path.basename annexPath
				[annexType] = (regex.annexType.exec annexFile).slice 1
				return cb new Error "Unknown annex type #{annexType}" unless (validAnnexTypes.indexOf annexType) > -1
				fs.readFile annexFile, "utf8", (err, data) ->
					annexConfig = JSON.parse data
					annexConfig.type
					console.log annexConfig
					cb()
			async.forEach files, processAnnex, ->
				console.log arguments
				cb()

