module Test.Main where

import Prelude
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Data.Maybe (Maybe(..))
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Aff (launchAff, forkAff, delay)
import Control.Monad.Aff.AVar (AVAR)
import Control.Parallel.Class (class Parallel, parallel)

import Pipes.Aff as Pipes
import Pipes.Aff (Buffer(..))
import Pipes.Prelude
import Pipes.Core
import Pipes hiding (discard)

type FoldP st evt m = st -> evt -> Tuple st (Maybe (Producer evt m Unit))

pux
  :: ∀ st m evt eff c
   . MonadAff (avar :: AVAR | eff) m
  => Parallel (Aff (avar :: AVAR | eff)) m
  => Maybe (Producer evt (Aff (avar :: AVAR | eff)) c) -- external events
  -> FoldP st evt m                                    -- the reducer
  -> st                                                -- initial state
  -> Producer st m Unit
pux mExtEvts foldp initialState = do
  -- spawn a channel for receiving and sending events
  -- we use this internal channel to mix external events with events generated
  -- during the evaluation of foldp.
  { input, output } <- lift $ liftAff $ Pipes.spawn Unbounded

  -- Evaluate the event producer in a fork
  case mExtEvts of
    Nothing -> pure unit
    Just extEvts -> void $ lift $ liftAff do
      forkAff do
        runEffect $ for extEvts \evt -> void do
          lift $ Pipes.send output evt

  -- Evaluate the events into foldp
  Pipes.fromInput input >->
    let loop st = do
          evt <- await
          let st' /\ mProducer = foldp st evt
          loop st' <* case mProducer of
            Nothing -> pure unit
            Just p ->
              lift $ liftAff do
                parallel do
                  runEffect $ for p \evt -> void do
                    lift $ liftAff $ Pipes.send output evt
     in loop initialState

main :: forall e. Eff _ Unit
main = void $ launchAff do
  { input, output, seal } <- Pipes.spawn Unbounded
  _ <- forkAff do
    let loop = do
          delay (100.0 # Milliseconds)
          Pipes.send output "hi there"
    loop
  runEffect $ for (Pipes.fromInput input) $ lift <<< log
