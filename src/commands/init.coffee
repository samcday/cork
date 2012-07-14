fs = require "fs"
{app} = flatiron = require "flatiron"

module.exports = (cb) ->
	return app.log.error "Cannot create a new Cork app when inside an existing one!" if app.cork
	
	fs.writeFileSync "#{process.cwd()}/cork.json", "{\n}"
