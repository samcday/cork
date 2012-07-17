_ = require "underscore"
glob = require "glob"
fs = require "fs"
path = require "path"
async = require "async"

validAnnexTypes = ["content", "blog"]

regex = 
	annexType: /^(.*?)\.annex$/

fileIgnores = [
	/^node_modules\/?/
	/\.gitignore$/
	/\.npmignore$/
	/\.annex$/
	/cork\.json$/
]

class CorkAnnex
	constructor: (@cork, @type, @config, @root) ->
		handlerName = "cork-#{@type}-#{@config.handler}"
		handlerPath = path.join @cork.root, @root, "node_modules", handlerName
		handler = (require handlerPath) @
	init: (cb) ->
		# We can't build the filelist until all annex roots have been discovered
		glob "**/*", (root: path.join @cork.root, @root), (err, matches) ->
			matches = _.select matches, (match) -> not _.any fileIgnores, (item) -> item.test match
			console.log "lol", matches
			cb()
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
				annexPath = path.dirname annexPath
				[annexType] = (regex.annexType.exec annexFile).slice 1
				return cb new Error "Unknown annex type #{annexType}" unless (validAnnexTypes.indexOf annexType) > -1
				fs.readFile annexFile, "utf8", (err, data) ->
					annexConfig = JSON.parse data
					cb null, new CorkAnnex self, annexType, annexConfig, path.relative self.root, annexPath
			async.map files, processAnnex, (err, annexes) ->
				return cb err if err?
				self.annexes = annexes

				async.forEach self.annexes, (annex, cb) ->
					annex.init cb
				, cb
