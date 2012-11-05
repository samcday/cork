_ = require "underscore"
path = require "path"
glob = require "glob"
{Minimatch} = minimatch = require "minimatch"
async = require "async"
mkdirp = require "mkdirp"
fs = require "fs"

fileIgnores = [
	/^node_modules\/?/
	/\.gitignore$/
	/\.npmignore$/
	/\.annex$/
	/cork\.json$/
	/^out\/?/
]

module.exports = class Annex
	constructor: (@cork, @type, @config, @root) ->
		# FIXME: need a getter like this because @cork.app.log doens't exist yet
		self = @
		@fileHandlers = []

		Object.defineProperty @, "log", get: -> self.cork.log
		@config = @config or {}
		@name = @config.name or path.basename @root
		@outputRoot = @config.root or @root

		# Determine the handler to use for this annex. If this is an asset annex
		# with no handler, we use a built-in one.
		if not @config.handler and @type is "assets"
			@handler = (new DefaultAssetHandler @)
		else
			handlerName = "cork-#{@type}-#{@config.handler}"
			@handler = (@cork.rootModule.require handlerName) @
			# handlerPath = path.join @cork.root, "node_modules", handlerName
			# @handler = (require handlerPath) @
	init: (cb) ->
		return cb() unless @handler.init
		self = @
		@_getFileList (err, files) ->
			self.handler.init files, cb
	processAll: (cb) ->
		self = @
		@_getFileList (err, files) ->
			async.forEach files, self.processFile, cb
	processFile: (file, cb) =>
		handler = _.find @fileHandlers, (handler) -> handler.matcher.match file
		return cb() unless handler
		handler.fn file, cb
	writeFile: (outName, contents, cb) ->
		outFile = path.join @cork.outRoot, @outputRoot, outName
		outPath = path.dirname outFile
		mkdirp outPath, ->
			fs.writeFile outFile, contents, cb
	writePage: (outName, options, meta, content, cb) ->
		self = @
		{layout} = options or {}
		fns = []
		fns.push (cb) -> cb null, content
		if layout
			fns.push (content, cb) ->
				layoutAnnex = self.cork.findLayout layout
				layoutAnnex.layoutPage content, meta, cb
		fns.push (content, cb) ->
			self.writeFile outName, content, cb
		async.waterfall fns, cb
	pathTo: (file) ->
		return path.join @cork.root, @root, file
	addFileHandler: (filter, fn) ->
		@fileHandlers.push { matcher: (new Minimatch filter), fn: fn }
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