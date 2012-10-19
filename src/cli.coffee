flatiron = require "flatiron"
path = require "path"
fs = require "fs"
Cork = require "./cork"

module.exports = app = flatiron.app

app.use flatiron.plugins.cli,
	dir: path.join __dirname, "commands"
	usage: "pewpew!"
