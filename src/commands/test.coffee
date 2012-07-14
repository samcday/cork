{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	app.cork.npm.link "cork-plugin-content-markdown", ->
		console.log arguments