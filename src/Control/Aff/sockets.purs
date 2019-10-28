module Control.Aff.Sockets where

import Control.Coroutine (Consumer, Process, Producer, await, runProcess, transform, ($~))
import Control.Coroutine.Aff (Step(..))
import Control.Coroutine.Aff (produce', Emitter) as CA
import Control.Monad.Except (runExcept)
import Control.Monad.Rec.Class (class MonadRec, forever)
import Control.Monad.Trans.Class (lift)
import Control.Parallel (class Parallel)
import Data.Either (Either, fromRight)
import Data.Function.Uncurried (Fn2, runFn2)
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Effect.Uncurried (EffectFn1, EffectFn2, EffectFn4, runEffectFn1, runEffectFn2, runEffectFn4)
import Foreign (MultipleErrors)
import Foreign.Class (class Decode, class Encode)
import Foreign.Generic (decodeJSON, encodeJSON)
import Partial.Unsafe (unsafePartial)
import Prelude (Unit, bind, void, ($), (<<<), (==), unit)

foreign import data Connection :: Type

type Port = Int
type Host = String

type TCPOptions opts = {port :: Port, host :: Host, allowHalfOpen :: Boolean | opts}

defaultTCPOptions :: TCPOptions ()
defaultTCPOptions = {port: 7777, host: "localhost", allowHalfOpen: false}

----------------------------------------------------------------------------------------
---- A PRODUCER OF CONNECTIONS
----------------------------------------------------------------------------------------
-- type EmitFunction a r = (Either a r -> Effect Unit)
type EmitFunction a r = CA.Emitter Effect a r
type Emitter a r = EmitFunction a r -> Effect Unit
-- Emitter a r = (CA.Emitter Effect a r) -> Effect Unit = (Step a r -> m Unit) -> Effect Unit (na unwrap)

type Left a = a -> Either a Unit
type Right a = Unit -> Either a Unit -- Step.Finish?


-- x :: Either Int Unit
-- x = Left 10
--
-- y :: Either Unit Int
-- y = Right 10

foreign import createConnectionEmitterImpl :: forall opts.
  EffectFn4 (Connection -> Step Connection Unit) (Unit -> Step Connection Unit) (TCPOptions opts) (EmitFunction Connection Unit) Unit

-- createConnectionEmitter :: forall eff. TCPOptions
  -- -> (EmitFunction Connection Unit eff) -> Eff (avar :: AVAR | eff) Unit
createConnectionEmitter :: forall opts. TCPOptions opts -> Emitter Connection Unit
createConnectionEmitter = runEffectFn4 createConnectionEmitterImpl Emit Finish -- dit moet Step en Finish worden, denk ik.

-- A Producer for Connections.
connectionProducer :: forall opts m. MonadAff m =>
  TCPOptions opts -> Producer Connection m Unit
connectionProducer options = CA.produce' (createConnectionEmitter options) -- arg is recv

----------------------------------------------------------------------------------------
---- CONNECT TO SERVER
----------------------------------------------------------------------------------------
foreign import connectToServerImpl :: forall opts. EffectFn1 (TCPOptions opts) Connection

connectToServer :: forall opts m. MonadAff m => TCPOptions opts -> m Connection
connectToServer = liftEffect <<< runEffectFn1 connectToServerImpl

----------------------------------------------------------------------------------------
---- A PRODUCER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import createMessageEmitterImpl :: EffectFn2 Connection (String -> Effect Unit) Unit

-- createMessageEmitter :: forall eff. Connection -> Emitter String Unit eff
-- createMessageEmitter = runEffectFn4 createMessageEmitterImpl Left Right

createMessageEmitter :: Connection -> Emitter String Unit
createMessageEmitter connection emitfunction = runEffectFn2 createMessageEmitterImpl connection cb
  where
    cb :: String -> Effect Unit
    cb s = if s == "shutdown"
      then (unwrap emitfunction) $ Finish unit
      else (unwrap emitfunction) $ Emit s

messageProducer :: forall m. MonadAff m => Connection -> Producer String m Unit
messageProducer connection = CA.produce' (createMessageEmitter connection)

----------------------------------------------------------------------------------------
---- A CONSUMER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import writeMessageImpl :: Fn2 Connection String (Effect Boolean)

writeMessage :: forall m. MonadAff  m => Connection -> String -> m Boolean
writeMessage c m = liftEffect $ (runFn2 writeMessageImpl c m)

messageConsumer :: forall m. MonadAff m =>
  Connection -> Consumer String m Unit
messageConsumer connection = forever do
  message <- await
  void $ lift $ writeMessage connection message

----------------------------------------------------------------------------------------
---- A CONNECTIONCONSUMER
----------------------------------------------------------------------------------------
type ConnectionProcess m = Connection -> Process m Unit

connectionConsumer :: forall m.
  MonadAff m =>
  MonadRec m =>
  ConnectionProcess m -> Consumer Connection m Unit
connectionConsumer process = forever do
  connection <- await
  void $ lift $ runProcess (process connection)

----------------------------------------------------------------------------------------
---- PRODUCING AND CONSUMING AN ADT OVER A CONNECTION
----------------------------------------------------------------------------------------
-- | From a connection, produce instances of a, or possibly a list of de-serialisation errors.
dataProducer :: forall a m f.
  Decode a =>
  MonadAff m =>
  MonadRec m =>
  Parallel f m =>
  Connection -> Producer (Either MultipleErrors a) m Unit
dataProducer connection = (messageProducer connection) $~ (forever (transform (runExcept <<< decodeJSON)))

writeData :: forall m a. Encode a => MonadAff m => Connection -> a -> m Boolean
writeData c d = liftEffect $ (runFn2 writeMessageImpl c (encodeJSON d))

dataConsumer :: forall a m.
  Encode a =>
  MonadAff m =>
  Connection -> Consumer a m Unit
dataConsumer connection = forever do
  dt <- await
  void $ lift $ writeData connection dt

-- From a connection, produce instances of a. An uninformative error will be thrown if deserialisation fails.
dataProducer_ :: forall a m f.
  Decode a =>
  MonadAff m =>
  MonadRec m =>
  Parallel f m =>
  Connection -> Producer a m Unit
dataProducer_ connection = (messageProducer connection) $~ (transform (unsafePartial $ fromRight <<< runExcept <<< decodeJSON))
