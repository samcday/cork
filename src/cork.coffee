_ = require "underscore"
express = require "express"
watch = require "watch"
glob = require "glob"
fs = require "fs"
path = require "path"
async = require "async"
mkdirp = require "mkdirp"
rimraf = require "rimraf"
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

class DefaultAssetHandler
	constructor: (@annex) ->
	processFile: (file, cb) ->
		self = @
		fs.readFile (@annex.pathTo file), (err, contents) ->
			return cb err if err?
			self.annex.writeFile file, contents, cb

class Annex
	constructor: (@cork, @type, @config, @root) ->
		@config = @config or {}
		@name = @config.name or path.basename @root
		@outputRoot = @config.root or @root

		# Determine the handler to use for this annex. If this is an asset annex
		# with no handler, we use a built-in one.
		if not @config.handler and @type is "assets"
			@handler = (new DefaultAssetHandler @)
		else
			handlerName = "cork-#{@type}-#{@config.handler}"
			handlerPath = path.join @cork.root, "node_modules", handlerName
			@handler = (require handlerPath) @
	init: (cb) ->
		return cb() unless @handler.init
		self = @
		@_getFileList (err, files) ->
			self.handler.init files, cb
	processAll: (cb) ->
		self = @
		async.series [
			(cb) ->
				return cb() unless self.handler.processFile
				self._getFileList (err, files) ->
					async.forEach files, (file, cb) -> 
						self.handler.processFile file, cb
					, cb
			(cb) ->
				return cb() unless self.handler.finish
				self.handler.finish cb
		], cb
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
	layoutBlogPost: (post, cb) ->
		return post.content unless @handler.layoutBlogPost
		@handler.layoutBlogPost post, cb

class BlogAnnex extends Annex
	init: (cb) ->
		@posts = {}
		@postContent = {}
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
		self = @
		post = @posts[slug]
		post.content = content
		layout = @config.layout
		@_renderPost post, layout, content, (err, rendered) ->
			return cb err if err?
			self.writeContent outName, {layout: layout}, content, cb
	processAll: (cb) ->
		self = @
		super ->
			# Now we go ahead and generate the paginated view.
			async.series [
				(cb) -> self._generatePages cb
			], cb
	_renderPost: (post, layout, content, cb) ->
		if layout
			layoutAnnex = @cork.findLayout layout
			layoutAnnex.layoutBlogPost post, cb
		else
			# TODO: some kind of default layout?
			cb null, post.content
	_generatePages: (cb) ->
		self = @
		sortedPosts = (_.sortBy @posts, (post) -> post.date).reverse()
		postsPerPage = 10
		layout = @config.layout
		generatePage = (page, cb) ->
			start = (page - 1) * postsPerPage
			pagePosts = sortedPosts[start...(start + postsPerPage)]
			async.map pagePosts, (post, cb) ->
				self._renderPost post, layout, post.content, cb
			, (err, renderedPosts) ->
				outName = if page is 1 then "index.html" else "/page/#{page}"
				self.writeContent outName, { layout: layout }, (renderedPosts.join ""), cb

		pages = Math.ceil (Object.keys @posts).length / postsPerPage
		async.forEachSeries [1..pages], generatePage, cb

module.exports = class Cork
	constructor: (@root, @app) ->
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
		@app.log.info "Starting web server on port 4000"
		cb()
	watch: (cb) ->
		self = @
		watch.createMonitor @root, { filter: @_filterWatcher }, (monitor) ->
			self.monitor = monitor

			changeHandler = (file) ->
				return if self._filterWatcher file
				#self._findAnnex file
				# For now we just balete the output dir and recreate it on every change.
				async.series [
					(cb) -> rimraf self.outRoot, cb
					(cb) -> self.generate cb
				], ->
					self.app.log.info "Reloaded Cork app."
			monitor.on "changed", changeHandler
			monitor.on "created", changeHandler
			# TODO: delete handler.
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