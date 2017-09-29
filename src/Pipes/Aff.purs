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
  , output
  , input
  , split
  , seal
  , Buffer
  , Input
  , Output
  , Channel
  ) where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AffAVar, AVar, AVAR, makeVar, peekVar, tryPeekVar, takeVar, putVar)
import Control.Monad.Aff.Bus (BusR, BusW)
import Control.Monad.Aff.Bus as Bus
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Parallel.Class (sequential, parallel)
import Data.Foldable (oneOf)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Pipes (await, yield)
import Pipes.Core (Consumer_, Producer_)

type SealVar = AVar Unit

seal:: ∀ a eff. Channel a -> Aff (avar :: AVAR | eff) Unit
seal (UnboundedChannel sealVar _) = putVar sealVar unit
seal (NewChannel sealVar _ _) = putVar sealVar unit

data Channel a
  = UnboundedChannel SealVar (AVar a)
  | NewChannel SealVar (BusR a) (BusW a)

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
  -> AffAVar eff (Channel a)

spawn Unbounded = do
  sealVar <- makeVar
  var <- makeVar
  pure $ UnboundedChannel sealVar var

spawn New = do
  sealVar <- makeVar
  i /\ o <- Bus.split <$> Bus.make
  pure $ NewChannel sealVar i o

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
  tryPeekVar sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ putVar var a
      , parallel $ false <$ peekVar sealVar
      ]
send' a (Output (NewChannel sealVar _ busW)) = do
  tryPeekVar sealVar >>= case _ of
    Just _  -> pure false
    Nothing -> sequential $ oneOf
      [ parallel $ true  <$ Bus.write a busW
      , parallel $ false <$ peekVar sealVar
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
  tryPeekVar sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just   <$> takeVar var
      , parallel $ Nothing <$ peekVar sealVar
      ]
recv' (Input (NewChannel sealVar busR _)) = do
  tryPeekVar sealVar >>= case _ of
    Just _  -> pure Nothing
    Nothing -> sequential $ oneOf
      [ parallel $ Just    <$> Bus.read busR
      , parallel $ Nothing <$ peekVar sealVar
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
  -- | Bounded Int
  -- | Latest a
  -- | Newest Int

-- | Store an unbounded number of messages in a FIFO queue
unbounded :: ∀ a. Buffer a
unbounded = Unbounded

-- | Store an unbounded number of messages in a FIFO queue
new :: ∀ a. Buffer a
new = New

-- -- | Store a bounded number of messages, specified by the 'Int' argument
-- bounded :: ∀ a. Int -> Buffer a
-- bounded 1 = Single
-- bounded n = Bounded n
--
-- {-| Only store the 'Latest' message, beginning with an initial value
--     'Latest' is never empty nor full.
-- -}
-- latest :: a -> Buffer a
-- latest = Latest
--
-- {-| Like `Bounded`, but `send` never fails (the buffer is never full).
--     Instead, old elements are discard to make room for new elements
-- -}
-- newest :: Int -> Buffer a
-- newest 1 = New
-- newest n = Newest n
