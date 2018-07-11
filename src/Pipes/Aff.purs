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
import Effect.Aff (Aff, Error, delay, forkAff)
import Effect.Aff.AVar as AVar
import Effect.Aff.Class (class MonadAff, liftAff)
import Control.Parallel.Class (sequential, parallel)
import Data.Foldable (oneOf)
import Data.Maybe (Maybe(..))
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Pipes (await, yield)
import Pipes.Core (Consumer_, Producer_)

type SealVar = AVar.AVar Unit

seal:: ∀ a. Channel a -> Aff Unit
seal (UnboundedChannel sealVar _) = void $ AVar.tryPut unit sealVar
seal (NewestChannel sealVar    _) = void $ AVar.tryPut unit sealVar
seal (RealTimeChannel sealVar  _) = void $ AVar.tryPut unit sealVar

kill:: ∀ a. Error -> Channel a -> Aff Unit
kill e (UnboundedChannel sealVar v) = do
  AVar.kill e sealVar
  AVar.kill e v
kill e (NewestChannel sealVar v) = do
  AVar.kill e sealVar
  AVar.kill e v
kill e (RealTimeChannel sealVar v) = do
  AVar.kill e sealVar
  AVar.kill e v

data Channel a
  = UnboundedChannel SealVar (AVar.AVar a)
  | NewestChannel    SealVar (AVar.AVar a)
  | RealTimeChannel  SealVar (AVar.AVar a)

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
  :: ∀ a
   . Buffer a
  -> Aff (Channel a)

spawn Unbounded = do
  sealVar <- AVar.empty
  var <- AVar.empty
  pure $ UnboundedChannel sealVar var

spawn New = do
  sealVar <- AVar.empty
  var <- AVar.empty
  pure $ NewestChannel sealVar var

spawn RealTime = do
  sealVar <- AVar.empty
  var <- AVar.empty
  pure $ RealTimeChannel sealVar var

send
  :: ∀ a
   . a
  -> Channel a
  -> Aff Boolean
send a = send' a <<< output

send'
  :: ∀ a
   . a
  -> Output a
  -> Aff Boolean
send' a (Output (UnboundedChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ forkAff (AVar.put a var)
      , parallel $ false <$ AVar.read sealVar
      ]
send' a (Output (NewestChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ (AVar.tryTake var *> AVar.put a var)
      , parallel $ false <$ AVar.read sealVar
      ]
send' a (Output (RealTimeChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ (AVar.tryTake var *> do
          AVar.put a var
          liftAff $ delay $ 0.0 # Milliseconds
          AVar.tryTake var
        )
      , parallel $ false <$ AVar.read sealVar
      ]

recv
  :: ∀ a
   . Channel a
  -> Aff (Maybe a)
recv = recv' <<< input

recv'
  :: ∀ a
   . Input a
  -> Aff (Maybe a)
recv' (Input (UnboundedChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just    <$> AVar.take var
      , parallel $ Nothing <$  AVar.read sealVar
      ]
recv' (Input (NewestChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just    <$> AVar.take var
      , parallel $ Nothing <$  AVar.read sealVar
      ]
recv' c@(Input (RealTimeChannel sealVar var)) = do
  AVar.tryRead sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just    <$> AVar.take var
      , parallel $ Nothing <$  AVar.read sealVar
      ]

{-| Convert an 'Output' to a 'Pipes.Consumer'
-}
toOutput
  :: ∀ a m
   . MonadAff m
  => Channel a
  -> Consumer_ a m Unit
toOutput = toOutput' <<< output

toOutput'
  :: ∀ a m
   . MonadAff m
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
  :: ∀ a m
   . MonadAff m
  => Channel a
  -> Producer_ a m Unit
fromInput = fromInput' <<< input

fromInput'
  :: ∀ a m
   . MonadAff m
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
