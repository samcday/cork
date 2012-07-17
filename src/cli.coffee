flatiron = require "flatiron"
path = require "path"
fs = require "fs"
Cork = require "./cork"
npm = require "npm"

app = flatiron.app

app.use flatiron.plugins.cli,
	dir: path.join __dirname, "commands"
	usage: "pewpew!"

# Find the cork root, if it exists.
findRoot = (cb) ->
	root = process.cwd()
	while root isnt "/"
		if fs.existsSync path.resolve root, "cork.json"
			return cb root
		root = path.resolve root, ".."
	cb null

findRoot (root) ->
	startApp = ->
		app.start (err) ->
			console.log "k!"

	if root
		app.cork = cork = new Cork root if root
		app.cork.init (err) ->
			return console.error err if err # TODO:
			npmConfig = 
				prefix: root
			npm.load npmConfig, (err, npm) ->
				cork.npm = npm
				startApp()
	else startApp()
