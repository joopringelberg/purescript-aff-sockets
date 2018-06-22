module Main where

import Control.Aff.Sockets (ConnectionProcess, SocketEffects, connectionConsumer, connectionProducer, defaultTCPOptions, messageConsumer, messageProducer)
import Control.Coroutine (Process, Transformer, runProcess, transform, ($$), ($~))
import Control.Monad.Aff (Aff, launchAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Rec.Class (forever)
import Data.String (length)
import Prelude (Unit, ($), void, (<>), show)

main :: forall e. Eff (SocketEffects e) Unit
main = void $ launchAff $ runProcess server
  where

    server :: Process (Aff (SocketEffects e)) Unit
    server = (connectionProducer defaultTCPOptions) $$ (connectionConsumer connectionHandler)

    connectionHandler :: ConnectionProcess e
    connectionHandler connection =
      ((messageProducer connection) $~ countingCharacters) $$ (messageConsumer connection)

    countingCharacters :: Transformer String String (Aff (SocketEffects e)) Unit
    countingCharacters = forever (transform f)
      where
        f :: String -> String
        f s = s <> " (" <> show (length s) <> " karakters)"
