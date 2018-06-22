function createConnectionEmitterImpl(left, right, options, emit)
{
  var server = require('net').createServer(options);
  // Make the server accept connections.
  server.listen(options.port, options.host);
  // Return a new connection.
  server.on('connection',
    function(connection)
    {
      var c = emit( left(connection) )();
    });
  server.on('error',
    function( error )
    {
      // Show or log the error.
      server.close(function()
        {
          // log or show that all connections are terminated and the server has fully ended.
        });
      // Finish the Producer.
      emit(right({}))();
    });
}
exports.createConnectionEmitterImpl = createConnectionEmitterImpl;


function createStringEmitterImpl(left, right, event, connection, emit)
{
  connection.on(event,
    function(a)
    {
      emit(left(a))();
    });
}
exports.createStringEmitterImpl = createStringEmitterImpl;

function writeImpl_(s,d) {
  return function() { return s.write(d); };
}
exports.writeImpl_ = writeImpl_;
