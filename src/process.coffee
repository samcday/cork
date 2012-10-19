cli = require "./cli"
child_process = require "child_process"
path = require "path"
fs = require "fs"

# Find the cork root, if it exists.
findRoot = (cb) ->
	root = process.cwd()
	while root isnt "/"
		if (fs.existsSync path.resolve root, "cork.json") and (fs.existsSync path.resolve root, "index.js")
			return cb root
		root = path.resolve root, ".."
	cb null

findRoot (root) ->
	if root
		child = child_process.fork (path.resolve root, "index.js"), (process.argv.slice 2)
	else
		cli.start (err) ->
			console.log "global done."
