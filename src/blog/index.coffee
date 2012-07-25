
exports.Blog = class Blog
	constructor: ->
		@posts = []			# Blog posts sorted in reverse chronological order.
		@bySlug = {}		# Quick index into blog posts by slug.
		@categories = {}
		@tags = {}
	addPost: (slug, title, date, categories, tags) ->
		@postsBySlug[slug] = post =
			slug: slug
			title: title
			date: date
			categories: categories
			tags: tags
		insertIndex = _.sortedIndex @posts, post, (post) -> -(post.date)
		@posts.splice insertIndex, 0, post
		for category in categories
			@categories[category] ?= []
			@categories[category].push post
		for tag in tags
			@tags[tag] ?= []
			@tags[tag].push post
	removePost: (slug) ->
		post = @postsBySlug[slug]
		delete @postsBySlug[slug]
		notPostFn = (post) -> post.slug is slug
		@posts = _.reject @posts, notPostFn
		@tags[tag] = _.reject @tags[tag], notPostFn for each tag in post.tags
		@categories[category] = _.reject @categories[category], notPostFn for each category in post.categories
	# Returns the "neighbours" of a post, the previous and next posts in reverse
	# chronological order.
	getNeighbours: (slug) ->
		postIndex = (_.pluck @posts, "slug").indexOf slug
		prevPost = if postIndex < (@posts.length - 1) then @posts[postIndex + 1] else null
		nextPost = if postIndex > 0 then @posts[postIndex - 1] else null
		return [nextPost, prevPost]
