module Control.Aff.Sockets where

import Control.Coroutine (Consumer, Process, Producer, await, runProcess, transform, ($~))
import Control.Coroutine.Aff (produce')
import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.AVar (AVAR)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Uncurried (EffFn1, EffFn2, EffFn4, runEffFn1, runEffFn2, runEffFn4)
import Control.Monad.Except (runExcept)
import Control.Monad.Rec.Class (class MonadRec, forever)
import Control.Monad.Trans.Class (lift)
import Control.Parallel (class Parallel)
import Data.Either (Either(..), fromRight)
import Data.Foreign (MultipleErrors)
import Data.Foreign.Class (class Decode, class Encode)
import Data.Foreign.Generic (decodeJSON, encodeJSON)
import Data.Function.Uncurried (Fn2, runFn2)
import Partial.Unsafe (unsafePartial)
import Prelude (Unit, bind, void, ($), (<<<), (==), unit)

foreign import data SOCKETIO :: Effect
foreign import data Connection :: Type

type SocketEffects eff = (avar :: AVAR , socketio :: SOCKETIO | eff)

type Port = Int
type Host = String

type TCPOptions opts = {port :: Port, host :: Host, allowHalfOpen :: Boolean | opts}

defaultTCPOptions :: TCPOptions ()
defaultTCPOptions = {port: 7777, host: "localhost", allowHalfOpen: false}

----------------------------------------------------------------------------------------
---- A PRODUCER OF CONNECTIONS
----------------------------------------------------------------------------------------
type EmitFunction a r eff = (Either a r -> Eff (avar :: AVAR | eff) Unit)
type Emitter a r eff = EmitFunction a r eff -> Eff (avar :: AVAR | eff) Unit

type Left a = a -> Either a Unit
type Right a = Unit -> Either a Unit

foreign import createConnectionEmitterImpl :: forall eff opts. EffFn4 (avar :: AVAR | eff) (Left Connection) (Right Connection) (TCPOptions opts) (EmitFunction Connection Unit eff) Unit

-- createConnectionEmitter :: forall eff. TCPOptions
  -- -> (EmitFunction Connection Unit eff) -> Eff (avar :: AVAR | eff) Unit
createConnectionEmitter :: forall eff opts. TCPOptions opts -> Emitter Connection Unit eff
createConnectionEmitter = runEffFn4 createConnectionEmitterImpl Left Right

-- A Producer for Connections.
connectionProducer :: forall eff opts m. MonadAff (avar :: AVAR | eff) m =>
  TCPOptions opts -> Producer Connection m Unit
connectionProducer options = produce' (createConnectionEmitter options)

----------------------------------------------------------------------------------------
---- CONNECT TO SERVER
----------------------------------------------------------------------------------------
foreign import connectToServerImpl :: forall eff opts. EffFn1 (SocketEffects eff) (TCPOptions opts) Connection

connectToServer :: forall eff opts m. MonadAff (SocketEffects eff) m => TCPOptions opts -> m Connection
connectToServer = liftEff <<< runEffFn1 connectToServerImpl

----------------------------------------------------------------------------------------
---- A PRODUCER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import createMessageEmitterImpl :: forall eff. EffFn2 (avar :: AVAR | eff) Connection (String -> Eff (avar :: AVAR | eff) Unit) Unit

-- createMessageEmitter :: forall eff. Connection -> Emitter String Unit eff
-- createMessageEmitter = runEffFn4 createMessageEmitterImpl Left Right

createMessageEmitter :: forall eff. Connection -> Emitter String Unit eff
createMessageEmitter connection emitfunction = runEffFn2 createMessageEmitterImpl connection cb
  where
    cb :: String -> Eff (avar :: AVAR | eff) Unit
    cb s = if s == "shutdown"
      then emitfunction $ Right unit
      else emitfunction $ Left s

messageProducer :: forall eff m. MonadAff (SocketEffects eff) m =>
  Connection -> Producer String m Unit
messageProducer connection = produce' (createMessageEmitter connection)

----------------------------------------------------------------------------------------
---- A CONSUMER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import writeMessageImpl :: forall eff. Fn2 Connection String (Eff (SocketEffects eff) Boolean)

writeMessage :: forall eff m. MonadAff (SocketEffects eff) m => Connection -> String -> m Boolean
writeMessage c m = liftEff $ (runFn2 writeMessageImpl c m)

messageConsumer :: forall eff m. MonadAff (SocketEffects eff) m =>
  Connection -> Consumer String m Unit
messageConsumer connection = forever do
  message <- await
  void $ lift $ writeMessage connection message

----------------------------------------------------------------------------------------
---- A CONNECTIONCONSUMER
----------------------------------------------------------------------------------------
type ConnectionProcess m = Connection -> Process m Unit

connectionConsumer :: forall eff m.
  MonadAff (SocketEffects eff) m =>
  MonadRec m =>
  ConnectionProcess m -> Consumer Connection m Unit
connectionConsumer process = forever do
  connection <- await
  void $ lift $ runProcess (process connection)

----------------------------------------------------------------------------------------
---- PRODUCING AND CONSUMING AN ADT OVER A CONNECTION
----------------------------------------------------------------------------------------
-- | From a connection, produce instances of a, or possibly a list of de-serialisation errors.
dataProducer :: forall eff a m f.
  Decode a =>
  MonadAff (SocketEffects eff) m =>
  MonadRec m =>
  Parallel f m =>
  Connection -> Producer (Either MultipleErrors a) m Unit
dataProducer connection = (messageProducer connection) $~ (forever (transform (runExcept <<< decodeJSON)))

writeData :: forall eff m a. Encode a => MonadAff (SocketEffects eff) m => Connection -> a -> m Boolean
writeData c d = liftEff $ (runFn2 writeMessageImpl c (encodeJSON d))

dataConsumer :: forall eff a m.
  Encode a =>
  MonadAff (SocketEffects eff) m =>
  Connection -> Consumer a m Unit
dataConsumer connection = forever do
  dt <- await
  void $ lift $ writeData connection dt

-- From a connection, produce instances of a. An uninformative error will be thrown if deserialisation fails.
dataProducer_ :: forall eff a m f.
  Decode a =>
  MonadAff (SocketEffects eff) m =>
  MonadRec m =>
  Parallel f m =>
  Connection -> Producer a m Unit
dataProducer_ connection = (messageProducer connection) $~ (transform (unsafePartial $ fromRight <<< runExcept <<< decodeJSON))
