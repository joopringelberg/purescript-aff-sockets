module Control.Aff.Sockets where

import Control.Coroutine (Consumer, Producer, Transformer, Process, await, runProcess, transform, ($$), ($~))
import Control.Coroutine.Aff (produce)
import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.AVar (AVAR)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Uncurried (EffFn4, EffFn5, runEffFn4, runEffFn5)
import Control.Monad.Rec.Class (forever)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, runFn2)
import Data.String (length)
import Prelude (Unit, bind, show, void, ($), (<>))

foreign import data SOCKETIO :: Effect
foreign import data Socket :: Type

type SocketEffects eff = (avar :: AVAR , socketio :: SOCKETIO | eff)

type Port = Int
type Host = String

type TCPOptions = {port :: Port, host :: Host, allowHalfOpen :: Boolean}

defaultTCPOptions :: TCPOptions
defaultTCPOptions = {port: 0, host: "", allowHalfOpen: false}

----------------------------------------------------------------------------------------
---- COROUTINES
----------------------------------------------------------------------------------------
type EmitFunction a r eff = (Either a r -> Eff (avar :: AVAR | eff) Unit)
type Emitter a r eff = EmitFunction a r eff -> Eff (avar :: AVAR | eff) Unit
type Connection = Socket

foreign import createConnectionEmitterImpl :: forall eff. EffFn4 (avar :: AVAR | eff) (Connection -> Either Connection Unit) (Unit -> Either Connection Unit) TCPOptions (EmitFunction Connection Unit eff) Unit

-- createConnectionEmitter :: forall eff. TCPOptions
  -- -> (EmitFunction Connection Unit eff) -> Eff (avar :: AVAR | eff) Unit
createConnectionEmitter :: forall eff. TCPOptions -> Emitter Connection Unit eff
createConnectionEmitter = runEffFn4 createConnectionEmitterImpl Left Right

-- A Producer for Connections.
connectionProducer :: forall eff. TCPOptions -> Producer Connection (Aff (avar :: AVAR | eff)) Unit
connectionProducer options = produce (createConnectionEmitter options)

-- A Consumer for Connections.
consumeConnection :: forall a eff. Consumer Connection (Aff (SocketEffects eff)) Unit
consumeConnection = forever do
  connection <- await
  void $ lift $ runProcess (process connection)

  where
    process :: Connection -> Process (Aff (SocketEffects eff)) Unit
    process connection = (((messageProducer connection) $~ countingCharacters) $$ (messageSender connection))

    messageProducer :: Connection -> Producer String (Aff (SocketEffects eff)) Unit
    messageProducer = getData

    countingCharacters :: Transformer String String (Aff (SocketEffects eff)) Unit
    countingCharacters = forever (transform f)
      where
        f :: String -> String
        f s = s <> " (" <> show (length s) <> " karakters)"

    messageSender :: Connection -> Consumer String (Aff (SocketEffects eff)) Unit
    messageSender connection = forever do
      message <- await
      void $ liftEff $ write_ connection message


foreign import writeImpl_ :: forall eff. Fn2 Socket String (Eff (SocketEffects eff) Boolean)

write_ :: forall eff eff2. Socket -> String -> Eff (SocketEffects eff) Boolean
write_ = runFn2 writeImpl_

foreign import createStringEmitterImpl :: forall eff. EffFn5 (avar :: AVAR | eff) (String -> Either String Unit) (Unit -> Either String Unit) String Connection (EmitFunction String Unit eff) Unit

createStringEmitter :: forall eff. String -> Connection -> Emitter String Unit eff
createStringEmitter = (runEffFn5 createStringEmitterImpl) Left Right

-- connect :: forall eff. Socket -> Producer Connection (Aff (avar :: AVAR | eff)) Unit
-- connect sock = produce (createEmitter "connect" sock)

getData :: forall eff. Connection -> Producer String (Aff (avar :: AVAR | eff)) Unit
getData connection = produce (createStringEmitter "data" connection)
