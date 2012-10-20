_ = require "underscore"
util = require "../util"

exports.Blog = class Blog extends process.EventEmitter
	constructor: ->
		@posts = []			# Blog posts sorted in reverse chronological order.
		@bySlug = {}		# Quick index into blog posts by slug.
		@categories = {}
		@tags = {}
		@postsPerPage = 10
		@numPages = 0
		@base = ""
		Object.defineProperty @, "categoryNames", 
			get: => Object.keys @categories
		Object.defineProperty @, "tagNames", 
			get: => Object.keys @tags
	addPost: (slug, title, date, content, categories, tags) ->
		@removePost slug
		@bySlug[slug] = post =
			slug: slug
			title: title
			date: date
			categories: categories
			content: content
			tags: tags
		post.permalink = @_postPermalink post unless post.permalink 
		insertIndex = _.sortedIndex @posts, post, (post) -> -(post.date)
		@posts.splice insertIndex, 0, post
		@_postCategory category, post for category in categories if categories
		@_postTag tag, post for tag in tags if tags
		@numPages = Math.ceil @posts.length / @postsPerPage
		@emit "new", post
	removePost: (slug) ->
		post = @bySlug[slug]
		return unless post
		delete @bySlug[slug]
		notPostFn = (post) -> post.slug is slug
		@posts = _.reject @posts, notPostFn
		@tags[tag].posts = _.reject @tags[tag].posts, notPostFn for tag in post.tags if post.tags
		@categories[category].posts = _.reject @categories[category].posts, notPostFn for category in post.categories if post.categories
	# Returns the "neighbours" of a post, the previous and next posts in reverse
	# chronological order.
	getNeighbours: (slug) ->
		postIndex = (_.pluck @posts, "slug").indexOf slug
		prevPost = if postIndex < (@posts.length - 1) then @posts[postIndex + 1] else null
		nextPost = if postIndex > 0 then @posts[postIndex - 1] else null
		return [nextPost, prevPost]
	getPagePosts: (page) ->
		start = (page - 1) * @postsPerPage
		return @posts[start...(start + @postsPerPage)]
	_postTag: (name, post) ->
		tag = @tags[name] ?= 
			permalink: @_tagPermalink name
			posts: []
		tag.posts.push post
	_postCategory: (name, post) ->
		category = @categories[name] ?=
			permalink: @_categoryPermalink name
			posts: []
		category.posts.push post
	_tagPermalink: (tag) ->
		return "#{@base}/tag/#{util.sluggerize tag}/index.html"
	_categoryPermalink: (category) ->
		return "#{@base}/category/#{util.sluggerize category}/index.html"
	_postPermalink: (post) ->
		{slug, date} = post
		return "#{@base}/#{date.getFullYear()}/#{util.zeroFill(date.getMonth()+1, 2)}/#{util.zeroFill(date.getDate(), 2)}/#{slug}/index.html"
