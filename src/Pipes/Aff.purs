module Pipes.Aff (
    send
  , recv
  , spawn
  , fromInput
  , toOutput
  , unbounded
  , Buffer
  , Input
  , Output
  ) where

import Prelude
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Data.Array ((:))
import Data.Array as Array
import Data.Maybe (Maybe(..), maybe)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Aff.AVar (AffAVar, AVar, AVAR, makeVar, makeVar', modifyVar,
                              peekVar, takeVar, putVar)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Trans.Class (lift)
import Pipes.Core (Consumer_, Producer_)
import Pipes (await, yield)
import Unsafe.Coerce (unsafeCoerce)
import Debug.Trace

send :: ∀ eff a. Output eff a -> a -> Aff eff Boolean
send (Output _send) v = _send v

recv :: ∀ eff a. Input eff a -> Aff eff (Maybe a)
recv (Input _recv) = _recv

newtype Output eff a = Output (a -> Aff eff Boolean)
newtype Input eff a = Input (Aff eff (Maybe a))

spawn
  :: ∀ a eff
   . Buffer a
  -> AffAVar eff
      { input :: Input (avar :: AVAR | eff) a
      , output :: Output (avar :: AVAR | eff) a
      , seal :: AffAVar eff Unit
      }
spawn buffer = do
  sealed <- makeVar' false
  let seal = putVar sealed true

  var <- makeVar
  let
      sendOrEnd a = do
        peekVar sealed >>= if _
          then pure false
          else true <$ putVar var a
      readOrEnd = do
        peekVar sealed >>= if _
          then pure Nothing
          else Just <$> takeVar var

  pure {
    input: Input readOrEnd
  , output: Output sendOrEnd
  , seal
  }

{-| Convert an 'Output' to a 'Pipes.Consumer'
-}
toOutput
  :: ∀ a m eff
   . MonadAff eff m
  => Output eff a
  -> Consumer_ a m Unit
toOutput (Output send) = loop
  where
    loop = do
      a <- await
      alive <- lift (liftAff $ send a)
      when alive loop

{-| Convert an 'Input' to a 'Pipes.Producer'
-}
fromInput
  :: ∀ a m eff
   . MonadAff eff m
  => Input eff a
  -> Producer_ a m Unit
fromInput (Input recv) = loop
  where
    loop = do
      lift (liftAff recv) >>= case _ of
        Nothing -> pure unit
        Just v -> do
          yield v
          loop

data Buffer a
  = Unbounded
  -- | Bounded Int
  -- | Single
  -- | Latest a
  -- | Newest Int
  -- | New

-- | Store an unbounded number of messages in a FIFO queue
unbounded :: ∀ a. Buffer a
unbounded = Unbounded

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
