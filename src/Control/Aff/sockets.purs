module Control.Aff.Sockets where

import Control.Coroutine (Consumer, Producer, Process, await, runProcess)
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
import Prelude (Unit, bind, void, ($))

foreign import data SOCKETIO :: Effect
foreign import data Socket :: Type

type SocketEffects eff = (avar :: AVAR , socketio :: SOCKETIO | eff)

type Port = Int
type Host = String

type TCPOptions = {port :: Port, host :: Host, allowHalfOpen :: Boolean}

defaultTCPOptions :: TCPOptions
defaultTCPOptions = {port: 0, host: "localhost", allowHalfOpen: false}

----------------------------------------------------------------------------------------
---- A PRODUCER OF CONNECTIONS
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

----------------------------------------------------------------------------------------
---- A PRODUCER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import createMessageEmitterImpl :: forall eff. EffFn5 (avar :: AVAR | eff) (String -> Either String Unit) (Unit -> Either String Unit) String Connection (EmitFunction String Unit eff) Unit

createMessageEmitter :: forall eff. String -> Connection -> Emitter String Unit eff
createMessageEmitter = (runEffFn5 createMessageEmitterImpl) Left Right

messageProducer :: forall eff. Connection -> Producer String (Aff (SocketEffects eff)) Unit
messageProducer connection = produce (createMessageEmitter "data" connection)

----------------------------------------------------------------------------------------
---- A CONSUMER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import writeMessageImpl :: forall eff. Fn2 Socket String (Eff (SocketEffects eff) Boolean)

writeMessage :: forall eff eff2. Socket -> String -> Eff (SocketEffects eff) Boolean
writeMessage = runFn2 writeMessageImpl

messageConsumer :: forall eff. Connection -> Consumer String (Aff (SocketEffects eff)) Unit
messageConsumer connection = forever do
  message <- await
  void $ liftEff $ writeMessage connection message

----------------------------------------------------------------------------------------
---- A CONNECTIONCONSUMER
----------------------------------------------------------------------------------------
type ConnectionProcess e = Connection -> Process (Aff (SocketEffects e)) Unit

connectionConsumer :: forall a eff. ConnectionProcess eff -> Consumer Connection (Aff (SocketEffects eff)) Unit
connectionConsumer process = forever do
  connection <- await
  void $ lift $ runProcess (process connection)
