fs = require "fs"
cli = require "../cli"

module.exports = (cb) ->
	cli.cork.generate cb
