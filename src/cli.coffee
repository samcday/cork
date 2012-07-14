flatiron = require "flatiron"
path = require "path"

app = flatiron.app

app.use flatiron.plugins.cli,
	dir: path.join __dirname, "commands"
	usage: "pewpew!"

app.start (err) ->
	console.log "k!"
