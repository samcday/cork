module.exports = util = require "util"

util.safeJSON = 
	# Parses JSON safely. Assumes the caller has a relevant callback that can be
	# notified of the failures gracefully.
	parse: (str, cb) ->
		try
			return JSON.parse str
		catch error
			cb new Error "Error parsing JSON" if cb
			return null

util.sluggerize = (text) ->
	# Ripped from http://stackoverflow.com/questions/1053902/how-to-convert-a-title-to-a-url-slug-in-jquery
	return text.toLowerCase().replace(/[^\w ]+/g, '').replace(/\s+/g, '-')

util.zeroFill = `function ( number, width )
{
  width -= number.toString().length;
  if ( width > 0 )
  {
    return new Array( width + (/\./.test( number ) ? 2 : 1) ).join( '0' ) + number;
  }
  return number + ""; // always return a string
}`