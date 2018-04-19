module Pipes.Aff (
    send
  , recv
  , send'
  , recv'
  , spawn
  , fromInput
  , fromInput'
  , toOutput
  , toOutput'
  , unbounded
  , new
  , realTime
  , output
  , input
  , split
  , seal
  , kill
  , Buffer
  , Input
  , Output
  , Channel
  ) where

import Prelude
import Control.Monad.Aff (Aff, Error, delay, forkAff)
import Control.Monad.Aff.AVar (AVAR, AVar, killVar, makeEmptyVar, putVar, readVar, takeVar, tryPutVar, tryReadVar, tryTakeVar)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Parallel.Class (sequential, parallel)
import Data.Foldable (oneOf)
import Data.Maybe (Maybe(..))
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Pipes (await, yield)
import Pipes.Core (Consumer_, Producer_)

type SealVar = AVar Unit

seal:: ∀ a eff. Channel a -> Aff (avar :: AVAR | eff) Unit
seal (UnboundedChannel sealVar _) = void $ tryPutVar unit sealVar
seal (NewestChannel sealVar    _) = void $ tryPutVar unit sealVar
seal (RealTimeChannel sealVar  _) = void $ tryPutVar unit sealVar

kill:: ∀ a eff. Error -> Channel a -> Aff (avar :: AVAR | eff) Unit
kill e (UnboundedChannel sealVar v) = do
  killVar e sealVar
  killVar e v
kill e (NewestChannel sealVar v) = do
  killVar e sealVar
  killVar e v
kill e (RealTimeChannel sealVar v) = do
  killVar e sealVar
  killVar e v

data Channel a
  = UnboundedChannel SealVar (AVar a)
  | NewestChannel    SealVar (AVar a)
  | RealTimeChannel  SealVar (AVar a)

newtype Input a = Input (Channel a)
newtype Output a = Output (Channel a)

input :: ∀ a. Channel a -> Input a
input = Input

output :: ∀ a. Channel a -> Output a
output = Output

split
  :: ∀ a
   . Channel a
  -> Tuple (Input a) (Output a)
split channel = Input channel /\ Output channel

spawn
  :: ∀ a eff
   . Buffer a
  -> Aff (avar :: AVAR | eff) (Channel a)

spawn Unbounded = do
  sealVar <- makeEmptyVar
  var <- makeEmptyVar
  pure $ UnboundedChannel sealVar var

spawn New = do
  sealVar <- makeEmptyVar
  var <- makeEmptyVar
  pure $ NewestChannel sealVar var

spawn RealTime = do
  sealVar <- makeEmptyVar
  var <- makeEmptyVar
  pure $ RealTimeChannel sealVar var

send
  :: ∀ eff a
   . a
  -> Channel a
  -> Aff (avar :: AVAR | eff) Boolean
send a = send' a <<< output

send'
  :: ∀ eff a
   . a
  -> Output a
  -> Aff (avar :: AVAR | eff) Boolean
send' a (Output (UnboundedChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ forkAff (putVar a var)
      , parallel $ false <$ readVar sealVar
      ]
send' a (Output (NewestChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ (tryTakeVar var *> putVar a var)
      , parallel $ false <$ readVar sealVar
      ]
send' a (Output (RealTimeChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ (tryTakeVar var *> do
          putVar a var
          liftAff $ delay $ 0.0 # Milliseconds
          tryTakeVar var
        )
      , parallel $ false <$ readVar sealVar
      ]

recv
  :: ∀ eff a
   . Channel a
  -> Aff (avar :: AVAR | eff) (Maybe a)
recv = recv' <<< input

recv'
  :: ∀ eff a
   . Input a
  -> Aff (avar :: AVAR | eff) (Maybe a)
recv' (Input (UnboundedChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just   <$> takeVar var
      , parallel $ Nothing <$ readVar sealVar
      ]
recv' (Input (NewestChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just   <$> takeVar var
      , parallel $ Nothing <$ readVar sealVar
      ]
recv' c@(Input (RealTimeChannel sealVar var)) = do
  tryReadVar sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just    <$> takeVar var
      , parallel $ Nothing <$ readVar sealVar
      ]

{-| Convert an 'Output' to a 'Pipes.Consumer'
-}
toOutput
  :: ∀ a m eff
   . MonadAff (avar :: AVAR | eff) m
  => Channel a
  -> Consumer_ a m Unit
toOutput = toOutput' <<< output

toOutput'
  :: ∀ a m eff
   . MonadAff (avar :: AVAR | eff) m
  => Output a
  -> Consumer_ a m Unit
toOutput' out = loop
  where
    loop = do
      a <- await
      alive <- liftAff $ send' a out
      when alive loop

{-| Convert an 'Input' to a 'Pipes.Producer'
-}
fromInput
  :: ∀ a m eff
   . MonadAff (avar :: AVAR | eff) m
  => Channel a
  -> Producer_ a m Unit
fromInput = fromInput' <<< input

fromInput'
  :: ∀ a m eff
   . MonadAff (avar :: AVAR | eff) m
  => Input a
  -> Producer_ a m Unit
fromInput' inp = loop
  where
    loop = do
      liftAff (recv' inp)  >>= case _ of
        Nothing -> pure unit
        Just v -> do
          yield v
          loop

data Buffer a
  = Unbounded
  | New
  | RealTime
  -- | Bounded Int
  -- | Latest a
  -- | Newest Int

-- | Store an unbounded number of messages in a FIFO queue
unbounded :: ∀ a. Buffer a
unbounded = Unbounded

-- | Store an unbounded number of messages in a FIFO queue
new :: ∀ a. Buffer a
new = New

-- |
realTime :: ∀ a. Buffer a
realTime = RealTime
