_ = require "underscore"
express = require "express"
watch = require "watch"
gaze = require "gaze"
chokidar = require "chokidar"
glob = require "glob"
minimatch = require "minimatch"
fs = require "fs"
path = require "path"
async = require "async"
mkdirp = require "mkdirp"
rimraf = require "rimraf"
{safeJSON} = util = require "./util"

Annex = require "./annex"
LayoutAnnex = require "./annexes/layout"
BlogAnnex = require "./annexes/blog"

validAnnexTypes = ["content", "blog", "layout", "assets"]

regex = 
	annexType: /^(.*?)\.annex$/

fileIgnores = [
	/^node_modules\/?/
	/\.gitignore$/
	/\.npmignore$/
	/\.annex$/
	/cork\.json$/
	/^out\/?/
]

watcherIgnores = [
	/(?:\/|^)(?:\.git$|\.git\/.*)$/
	/(?:\/|^)(?:node_modules$|node_modules\/.*)$/
	/\/\..*/
]

class DefaultAssetHandler
	constructor: (@annex) ->
	processFile: (file, cb) ->
		self = @
		fs.readFile (@annex.pathTo file), (err, contents) ->
			return cb err if err?
			self.annex.writeFile file, contents, cb

module.exports = class Cork
	constructor: (@rootModule, @log) ->
		@root = path.dirname @rootModule.filename
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
		self = @
		# Process layouts first.
		processAnnexes = (cb, annexes) ->
			async.forEachSeries annexes, (annex, cb) ->
				annex.processAll cb
			, cb
		async.series [
			(cb) -> rimraf self.outRoot, cb
			(cb) ->
				processAnnexes cb, self.layoutAnnexes = _.select self.annexes, (annex) ->
					return annex instanceof LayoutAnnex
			(cb) ->
				processAnnexes cb, _.reject self.annexes, (annex) ->
					return annex instanceof LayoutAnnex
		], cb		
	server: (cb) ->
		server = @server = express.createServer()
		server.use express.static @outRoot
		server.use express.directory @outRoot
		server.listen 4000
		@log.info "Starting web server on port 4000"
		cb()
	watch: (cb) ->
		self = @

		watcher = chokidar.watch @root, 
			persistent: true
			ignored: (file) ->
				return true if 0 is file.indexOf self.outRoot
				relativePath = path.relative self.root, file
				return true if _.any watcherIgnores, (ignore) -> ignore.test relativePath
				console.log "#{file}?"
				return false
		watcher.on "all", (op, file) ->
			console.log op, file
		cb()
	findLayout: (name) ->
		_.detect @layoutAnnexes, (annex) -> return annex.name is name
	_filterWatcher: (file) =>
		return true if (file.indexOf @outRoot) is 0
		return true if (file.indexOf "#{@root}/node_modules") is 0
		return true if (file.indexOf "#{@root}/.git") is 0
		return false
	# Finds the annex that 'owns' a file.
	_findAnnex: (file) ->
		file = path.relative @root, file
		base = path.dirname file
		annex = _.max @annexes, (annex) ->
			return 0 unless (base.indexOf annex.root) is 0
			return annex.root.length
	# Load the main configuration from cork.json
	_loadConfig: (cb) =>
		fs.readFile (path.join @root, "cork.json"), "utf8", (err, data) =>
			return cb err if err?
			return unless @config = safeJSON.parse data, cb
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
				fs.readFile (path.join annexPath, annexFile), "utf8", (err, data) ->
					return unless annexConfig = safeJSON.parse data, cb
					annexClass = switch annexType
						when "layout" then LayoutAnnex
						when "blog" then BlogAnnex
						else Annex
					cb null, new annexClass self, annexType, annexConfig, path.relative self.root, annexPath
			async.mapSeries files, processAnnex, (err, annexes) ->
				return cb err if err?
				self.annexes = annexes
				cb()
	_initAnnexes: (cb) =>
		self = @
		initAnnexes = (cb, annexes) ->
			async.forEach annexes, (annex, cb) ->
				annex.init cb
			, cb

		# Init layouts first.
		async.series [
			(cb) ->
				initAnnexes cb, self.layoutAnnexes = _.select self.annexes, (annex) ->
					return annex instanceof LayoutAnnex
			(cb) ->
				initAnnexes cb, _.reject self.annexes, (annex) ->
					return annex instanceof LayoutAnnex
		], cb