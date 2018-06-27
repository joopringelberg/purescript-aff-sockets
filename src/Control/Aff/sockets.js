function createConnectionEmitterImpl(left, right, options, emit)
{
  const server = require('net').createServer(options);

  // Make the server accept connections.
  server.listen(options.port, options.host);
  // Return a new connection.
  server.on('connection',
    function(connection)
    {
      emit( left(connection) )();
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


function createMessageEmitterImpl(connection, emit)
{
  connection.on("data",
    function(a)
    {
      emit(a + "")();
    });
  connection.on('error',
    function(error)
    {
      // Show or log the error.
      connection.close(function()
        {
          // show or log that the connection is fully closed.
        });
      // Finish the producer.
      emit("shutdown")();
    });
  connection.on('end',
    function()
    {
      // Finish the producer.
      emit("shutdown")();
    });
  connection.on('close',
    function()
    {
      // Finish the producer.
      emit("shutdown")();
    });
}
exports.createMessageEmitterImpl = createMessageEmitterImpl;

function writeMessageImpl(s,d) {
  return function() { return s.write(d); };
}
exports.writeMessageImpl = writeMessageImpl;

function connectToServerImpl(o) {
  return require('net').createConnection(o);
}
exports.connectToServerImpl = connectToServerImpl;
