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
{Blog} = blog = require "./blog"
util = require "./util"

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
		handler = _.find @fileHandlers, (handler) -> handler.filter.test file
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
		@fileHandlers.push { filter: filter, fn: fn }
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
	layoutPage: (content, meta, cb) ->
		@handler.layoutPage content, meta, cb
	layoutBlogPost: (blogAnnex, post, archive, cb) ->
		return cb() unless @handler.layoutBlogPost
		meta =
			archive: archive
		@handler.layoutBlogPost blogAnnex.blog, post, meta, cb
	layoutBlogCategory: (name, posts, cb) ->
		return cb() unless @handler.layoutBlogCategory
		@handler.layoutBlogCategory "category", name, posts, cb
	layoutBlogArchive: (blogAnnex, page, renderedPosts, cb) ->
		throw "Not implemented" unless @handler.layoutBlogArchive
		@handler.layoutBlogArchive blogAnnex.blog, page, renderedPosts, cb
	layoutBlogTag: (name, posts, cb) ->
		return cb() unless @handler.layoutBlogCategory
		@handler.layoutBlogCategory "tag", name, posts, cb

class BlogAnnex extends Annex
	init: (cb) ->
		@blog = new Blog
		@blog.base = "/#{@root}"
		super cb
	processAll: (cb) ->
		self = @
		super ->
			async.series [
				(cb) -> async.forEach (Object.keys self.blog.bySlug), self._generatePostPage, cb
				(cb) -> self._generateArchive cb
				(cb) -> self._generateCategoryPages cb
				(cb) -> self._generateTagPages cb
			], cb
	_writeBlogPage: (outName, options, content, cb) ->
		@writePage outName, options, @_generateBlogMeta(), content, cb
	_renderPost: (post, layout, archive, cb) ->
		if layout
			layoutAnnex = @cork.findLayout layout
			layoutAnnex.layoutBlogPost @, post, archive, (err, out) ->
				return cb err if err?
				cb null, out # or content
		else
			# TODO: some kind of default layout?
			cb null, post.content
	_generateBlogMeta: ->
		meta =
			type: "blog"
			blog:
				categories: @blog.categoryNames.sort().map (name) =>
					category = @blog.categories[name]
					return {
						name: name
						count: category.posts.length
						permalink: category.permalink
					}
				tags: @blog.tagNames.sort().map (name) =>
					tag = @blog.tags[name]
					return {
						name: name
						count: tag.posts.length
						permalink: tag.permalink
					}
		return meta
	_generatePostPage: (slug, cb) =>
		post = @blog.bySlug[slug]
		outName = (post.permalink.substring @root.length + 1) + "index.html"
		layout = post.layout or @config.layout
		@_renderPost post, layout, false, (err, rendered) =>
			return cb err if err?
			@_writeBlogPage outName, { layout: layout }, rendered, cb
	_generateArchive: (cb) ->
		layout = @config.layout
		layoutAnnex = @cork.findLayout layout
		generatePage = (page, cb) =>
			async.map (@blog.getPagePosts page), (post, cb) =>
				@_renderPost post, layout, true, cb
			, (err, renderedPosts) =>
				outName = if page is 1 then "index.html" else "/page/#{page}/index.html"
				layoutAnnex.layoutBlogArchive @, page, renderedPosts, (err, content) =>
					@_writeBlogPage outName, { layout: layout }, content, cb
		async.forEachSeries [1..@blog.numPages], generatePage, cb
	_generateCategoryPages: (cb) ->
		layout = @config.layout
		layoutAnnex = @cork.findLayout layout
		generateCategoryPage = (name, cb) =>
			category = @blog.categories[name]
			outName = (category.permalink.substring @root.length + 1) + "index.html"
			layoutAnnex.layoutBlogCategory name, category.posts, (err, content) =>
				return cb err if err
				@_writeBlogPage outName, { layout: layout }, content, cb
		async.forEachSeries @blog.categoryNames, generateCategoryPage, cb
	_generateTagPages: (cb) ->
		layout = @config.layout
		layoutAnnex = @cork.findLayout layout
		generateTagPage = (name, cb) =>
			tag = @blog.tags[name]
			outName = (tag.permalink.substring @root.length + 1) + "index.html"
			layoutAnnex.layoutBlogTag name, tag.posts, (err, content) =>
				return cb err if err
				@_writeBlogPage outName, { layout: layout }, content, cb
		async.forEachSeries @blog.tagNames, generateTagPage, cb

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
		watch.createMonitor @root, { filter: @_filterWatcher }, (monitor) ->
			self.monitor = monitor

			changeHandler = (file) ->
				return if self._filterWatcher file
				#self._findAnnex file
				self.generate ->
					self.log.info "Reloaded Cork app."
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