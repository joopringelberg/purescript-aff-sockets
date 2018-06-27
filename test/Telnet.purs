{-
Use this module's main function as a substitute for Telnet.
In other words, it functions as a client that connects to a given server.
Connect to the server that is in echo.purs (with default localhost and 7777):

  $pulp --psc-package test --main Telnet

while the server can be started like this:

  $pulp --psc-package test

The telnet function provides for a line reader that you can type into. The value will be echo'd by the echo server, adding the number of characters received.
-}

module Telnet where

import Prelude

import Control.Aff.Sockets (Connection, SocketEffects, ConnectionProcess, connectToServer, defaultTCPOptions, messageProducer, writeMessage)
import Control.Coroutine (Consumer, await, runProcess, ($$))
import Control.Monad.Aff (Aff, launchAff, runAff)
import Control.Monad.Aff.Console (log, CONSOLE)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Rec.Class (forever)
import Control.Monad.Trans.Class (lift)
import Data.Options ((:=))
import Node.Process (stdin, stdout) as Process
import Node.ReadLine (READLINE, completer, createInterface, noCompletion, output, setLineHandler, setPrompt)

type TelnetEffects e = SocketEffects (readline :: READLINE, console :: CONSOLE | e)

main :: forall e. Eff (TelnetEffects e) Unit
main = void $ launchAff do
  connection <- connectToServer defaultTCPOptions
  createInterfaceAff connection
  runProcess $ client connection

  where

    client :: ConnectionProcess (Aff (TelnetEffects e))
    client connection =
      (messageProducer connection) $$ consumeMessageAndShow

    consumeMessageAndShow :: Consumer String (Aff (TelnetEffects e)) Unit
    consumeMessageAndShow = forever do
      message <- await
      lift (log ("incoming: " <> message))


    lineHandler :: Connection -> String -> Eff (TelnetEffects e) Unit
    lineHandler connection s = void $ runAff (const (pure unit)) (writeMessage connection s)

    createInterfaceAff :: Connection -> Aff (TelnetEffects e) Unit
    createInterfaceAff connection = liftEff $ do
      interface <- createInterface Process.stdin
        (output := Process.stdout <>
        completer := noCompletion)
      setPrompt ">>" 0 interface
      setLineHandler interface (lineHandler connection)
