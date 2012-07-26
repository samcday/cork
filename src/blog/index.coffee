_ = require "underscore"

exports.Blog = class Blog extends process.EventEmitter
	constructor: ->
		@posts = []			# Blog posts sorted in reverse chronological order.
		@bySlug = {}		# Quick index into blog posts by slug.
		@categories = {}
		@tags = {}
		@postsPerPage = 10
		@numPages = 0
		@base = ""
	addPost: (slug, title, date, content, categories, tags) ->
		@bySlug[slug] = post =
			slug: slug
			title: title
			date: date
			categories: categories
			content: content
			tags: tags
		post.permalink = @generatePermalink post unless post.permalink 
		insertIndex = _.sortedIndex @posts, post, (post) -> -(post.date)
		@posts.splice insertIndex, 0, post
		if categories
			for category in categories
				@categories[category] ?= []
				@categories[category].push post
		if tags
			for tag in tags
				@tags[tag] ?= []
				@tags[tag].push post
		@numPages = Math.ceil @posts.length / @postsPerPage
		@emit "new", post
	generatePermalink: (post) ->
		{slug, date} = post
		return "#{@base}/#{date.getFullYear()}/#{date.getMonth()+1}/#{date.getDate()}/#{slug}/index.html"
	removePost: (slug) ->
		post = @bySlug[slug]
		delete @bySlug[slug]
		notPostFn = (post) -> post.slug is slug
		@posts = _.reject @posts, notPostFn
		@tags[tag] = _.reject @tags[tag], notPostFn for tag in post.tags
		@categories[category] = _.reject @categories[category], notPostFn for category in post.categories
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
