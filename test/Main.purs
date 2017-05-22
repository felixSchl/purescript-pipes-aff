module Test.Main where

import Prelude
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Data.Maybe (Maybe(..), isJust)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Aff (launchAff, forkAff, delay)
import Control.Monad.Aff.Unsafe
import Control.Monad.Aff.AVar (AVAR)
import Control.Parallel.Class (class Parallel, parallel, sequential)
import Data.Newtype (unwrap)

import Pipes.Aff as Pipes
import Pipes.Aff (Buffer(..))
import Pipes.Prelude hiding (show)
import Pipes.Core
import Pipes hiding (discard)

type FoldP st evt m = st -> evt -> Tuple st (Maybe (Producer evt m Unit))

pux
  :: ∀ st m evt eff c
   . MonadAff (avar :: AVAR | eff) m
  => m ~> Aff (avar :: AVAR | eff)
  -> Maybe (Producer evt (Aff (avar :: AVAR | eff)) c) -- external events
  -> st                                                -- initial state
  -> FoldP st evt m                                    -- the reducer
  -> Producer st m Unit
pux intoAff mExtEvts initialState foldp = do
  -- spawn a channel for interleaving external and internal events
  { input, output } <- lift $ liftAff $ Pipes.spawn New

  -- evaluate the external event producer in a fork
  case mExtEvts of
    Nothing -> pure unit
    Just extEvts -> void $ lift $ liftAff do
      forkAff do
        runEffect $ for extEvts \evt -> void do
          lift $ unsafeCoerceAff $ log "sending evt"
          lift $ Pipes.send output evt

  -- process each event, yielding a new state for each event
  Pipes.fromInput input >->
    let loop st = do
          lift $ liftAff $ unsafeCoerceAff $ log "... (1)"
          evt <- await
          lift $ liftAff $ unsafeCoerceAff $ log "... (2)"
          let st' /\ mProducer = foldp st evt
          lift $ liftAff $ unsafeCoerceAff $ log $ "... (3): " <> show (isJust mProducer)
          case mProducer of
            Nothing -> pure unit
            Just p ->
              lift $ liftAff do
                unsafeCoerceAff $ log "ok, applying sub prpoducer"
                intoAff $ runEffect $ for p \evt -> void do
                  lift $ liftAff $ unsafeCoerceAff $ log "piping it back"
                  lift $ liftAff $ Pipes.send output evt
          loop st'
     in loop initialState

main :: forall e. Eff _ Unit
main = void $ launchAff do

  let evtsP = do
        lift $ delay (0.0 # Milliseconds)
        yield 1
        yield 2
        yield 3

  let p = pux id (Just evtsP) 0 \st _ ->
            let st' = st + 1
                -- mP' = Nothing :: Maybe (Producer _ (Aff _) _)
                mP' = Just do
                        lift $ delay (0.0 # Milliseconds)
                        lift $ log "wow"
                        yield 10
                        pure unit
             in st' /\ mP'

  runEffect $ for p \st ->
    lift $ log $ "state changed: " <> show st
