module Main where


import Control.Aff.Sockets (Host, Port, SOCKETIO, TCPOptions, connectionProducer, consumeConnection, defaultTCPOptions)
import Control.Coroutine (runProcess, ($$))
import Control.Monad.Aff (launchAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.AVar (AVAR)
import Control.Monad.Eff.Console (CONSOLE)
import Control.Monad.Eff.Exception (EXCEPTION)
import Prelude (Unit, ($), void)

main :: forall e. Eff (exception :: EXCEPTION, console :: CONSOLE, socketio :: SOCKETIO, avar :: AVAR | e) Unit
main = echoLight "localhost" 7777

echoLight :: forall e. Host -> Port -> Eff (exception :: EXCEPTION, console :: CONSOLE, socketio :: SOCKETIO, avar :: AVAR | e) Unit
echoLight host port = void $ launchAff $ runProcess (connectionProducer options $$ consumeConnection)
  where
    options :: TCPOptions
    options = defaultTCPOptions {host = host, port = port}
