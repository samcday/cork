Annex = require "../annex"

module.exports = class LayoutAnnex extends Annex
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