async = require "async"
Annex = require "../annex"
Blog = require "../blog"

module.exports = class BlogAnnex extends Annex
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
