module Control.Aff.Sockets where

import Control.Coroutine (Consumer, Producer, Process, await, runProcess)
import Control.Coroutine.Aff (produce)
import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.AVar (AVAR)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Uncurried (EffFn1, EffFn4, runEffFn1, runEffFn4)
import Control.Monad.Rec.Class (forever)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, runFn2)
import Prelude (Unit, bind, void, ($), (<<<))

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

foreign import createConnectionEmitterImpl :: forall eff opts. EffFn4 (avar :: AVAR | eff) (Connection -> Either Connection Unit) (Unit -> Either Connection Unit) (TCPOptions opts) (EmitFunction Connection Unit eff) Unit

-- createConnectionEmitter :: forall eff. TCPOptions
  -- -> (EmitFunction Connection Unit eff) -> Eff (avar :: AVAR | eff) Unit
createConnectionEmitter :: forall eff opts. TCPOptions opts -> Emitter Connection Unit eff
createConnectionEmitter = runEffFn4 createConnectionEmitterImpl Left Right

-- A Producer for Connections.
connectionProducer :: forall eff opts. TCPOptions opts -> Producer Connection (Aff (avar :: AVAR | eff)) Unit
connectionProducer options = produce (createConnectionEmitter options)

----------------------------------------------------------------------------------------
---- CONNECT TO SERVER
----------------------------------------------------------------------------------------
foreign import connectToServerImpl :: forall eff opts. EffFn1 (SocketEffects eff) (TCPOptions opts) Connection

connectToServer :: forall eff opts. TCPOptions opts -> Aff (SocketEffects eff) Connection
connectToServer = liftEff <<< runEffFn1 connectToServerImpl

----------------------------------------------------------------------------------------
---- A PRODUCER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import createMessageEmitterImpl :: forall eff. EffFn4 (avar :: AVAR | eff) (String -> Either String Unit) (Unit -> Either String Unit) Connection (EmitFunction String Unit eff) Unit

createMessageEmitter :: forall eff. Connection -> Emitter String Unit eff
createMessageEmitter = runEffFn4 createMessageEmitterImpl Left Right

messageProducer :: forall eff. Connection -> Producer String (Aff (SocketEffects eff)) Unit
messageProducer connection = produce (createMessageEmitter connection)

----------------------------------------------------------------------------------------
---- A CONSUMER OF MESSAGES OVER A CONNECTION
----------------------------------------------------------------------------------------
foreign import writeMessageImpl :: forall eff. Fn2 Connection String (Eff (SocketEffects eff) Boolean)

writeMessage :: forall eff. Connection -> String -> Aff (SocketEffects eff) Boolean
writeMessage c m = liftEff $ (runFn2 writeMessageImpl c m)

messageConsumer :: forall eff. Connection -> Consumer String (Aff (SocketEffects eff)) Unit
messageConsumer connection = forever do
  message <- await
  void $ lift $ writeMessage connection message

----------------------------------------------------------------------------------------
---- A CONNECTIONCONSUMER
----------------------------------------------------------------------------------------
type ConnectionProcess e = Connection -> Process (Aff (SocketEffects e)) Unit

connectionConsumer :: forall eff. ConnectionProcess eff -> Consumer Connection (Aff (SocketEffects eff)) Unit
connectionConsumer process = forever do
  connection <- await
  void $ lift $ runProcess (process connection)
