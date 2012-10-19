{spawn} = require 'child_process' 

showinfo = (args) -> console.info("Spawn: ", args.join(" ")) 

module.exports = 
	passthru: (args...) -> 
		callback = -> 
		callback = args.pop() if "function" == typeof args[args.length-1] 
		showinfo(args) 
		proc = spawn '/usr/bin/env', args 
		proc.stdout.pipe process.stdout 
		proc.stderr.pipe process.stderr 
		proc.on 'exit', (code) -> 
			console.info("Exited with status: " + code) if code 
			callback(code) 

task 'build', 'Compile CoffeeScript to JavaScript.', -> 
	module.exports.passthru 'coffee', '-o', 'lib/', '-c', 'src/' 

task "watch", "Watch src/ for changes and compile them to lib/", ->
	module.exports.passthru "coffee", "-o", "lib/", "-w", "-c", "src/"