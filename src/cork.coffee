_ = require "underscore"
glob = require "glob"
fs = require "fs"
path = require "path"
async = require "async"
mkdirp = require "mkdirp"
{safeJSON} = util = require "./util"

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

class Annex
	constructor: (@cork, @type, @config, @root) ->
		@config = @config or {}
		@name = @config.name or path.basename @root
		handlerName = "cork-#{@type}-#{@config.handler}"
		handlerPath = path.join @cork.root, "node_modules", handlerName
		@handler = (require handlerPath) @
		@outputRoot = @config.root or @root
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
		outFile = path.join @cork.outRoot, @outputRoot, outName
		outPath = path.dirname outFile
		mkdirp outPath, ->
			fs.writeFile outFile, contents, cb
	writeContent: (outName, options, content, cb) ->
		self = @
		{layout} = options or {}
		fns = []
		fns.push (cb) -> cb null, content
		if layout
			fns.push (content, cb) ->
				layoutAnnex = self.cork.findLayout layout
				layoutAnnex.layoutContent content, cb
		fns.push (content, cb) ->
			self.writeFile outName, content, cb
		async.waterfall fns, cb
	pathTo: (file) ->
		return path.join @cork.root, @root, file
	_getFileList: (cb) ->
		self = @
		glob "**/*", (cwd: path.join @cork.root, @root, "/"), (err, matches) ->
			return cb err if err?

			# Filter out hardcoded ignores.
			matches = _.select matches, (match) -> not _.any fileIgnores, (item) -> item.test match

			# Filter out other annex roots.
			matches = _.select matches, (match) ->
				not _.any self.cork.annexes, (annex) ->
					return false if annex is self
					return false unless (path.normalize self.root) is path.dirname annex.root
					return (match.indexOf annex.root) is 0
			cb null, matches

class LayoutAnnex extends Annex
	layoutContent: (content, cb) ->
		@handler.layoutContent content, cb

class BlogAnnex extends Annex
	init: (cb) ->
		@posts = {}
		super cb
	addPost: (slug, title, date, categories, tags) ->
		# console.log "adding post.", arguments
		@posts[slug] =
			title: title
			date: date
			categories: categories
			tags: tags
	getPost: (slug) ->
		return @posts[slug]
	writePost: (slug, outName, layout, content, cb) ->
		@writeContent outName, {layout: layout}, content, cb

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
		async.forEachSeries @annexes, (annex, cb) ->
			annex.processAll cb
		, cb
	findLayout: (name) ->
		_.detect @layoutAnnexes, (annex) -> return annex.name is name
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