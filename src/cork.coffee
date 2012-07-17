_ = require "underscore"
glob = require "glob"
fs = require "fs"
path = require "path"
async = require "async"
mkdirp = require "mkdirp"

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
		@handler = (require handlerPath) @
	init: (cb) ->
		self = @
		@_getFileList (err, files) ->
			self.handler.init files, cb
	processAll: (cb) ->
		self = @
		@_getFileList (err, files) ->
			async.forEach files, (file, cb) -> 
				self.handler.processFile file, cb
			, cb
	writeFile: (outName, contents, cb) ->
		outFile = path.join @cork.outRoot, outName
		outPath = path.dirname outFile
		mkdirp outPath, ->
			fs.writeFile outFile, contents, cb
	_getFileList: (cb) ->
		self = @
		glob "**/*", (root: path.join @cork.root, @root), (err, matches) ->
			return cb err if err?
			matches = _.select matches, (match) -> not _.any fileIgnores, (item) -> item.test match
			cb null, matches

module.exports = class Cork
	constructor: (@root) ->
		@annexes = []
	init: (cb) ->
		async.series [
			@_loadConfig
			@_discoverAnnexes
			@_initAnnexes
		], (err) ->
			cb err
	# Goes through every annex and processes every file.
	generate: (cb) ->
		async.forEach @annexes, (annex, cb) ->
			annex.processAll cb
		, cb
	# Load the main configuration from cork.json
	_loadConfig: (cb) =>
		fs.readFile (path.join @root, "cork.json"), "utf8", (err, data) =>
			return cb err if err?
			@config = JSON.parse data
			@outRoot = path.join @root, @config?.generate?.outDir or "out"
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
				cb()
	_initAnnexes: (cb) =>		
		async.forEach @annexes, (annex, cb) ->
			annex.init cb
		, cb
