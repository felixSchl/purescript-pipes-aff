module Test.Main where

import Control.Monad.Aff.AVar
import Control.Parallel
import Data.Maybe
import Debug.Trace
import Pipes.Core
import Prelude

import Control.Monad.Aff (forkAff, delay, joinFiber, launchAff)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, modifyRef)
import Control.Monad.Rec.Class (tailRecM, Step(..), forever)
import Data.Array ((..), (:))
import Data.Array as Array
import Data.Foldable (for_, oneOf)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Pipes hiding (discard)
import Pipes.Aff (Buffer, fromInput, unbounded)
import Pipes.Aff as P
import Pipes.Prelude hiding (show,map)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run', defaultConfig)

data TestBufferType = TestUnbounded | TestNew
derive instance eqTestBuffer :: Eq TestBufferType

main :: Eff _ Unit
main = run' defaultConfig [consoleReporter] do
  describe "pipes-aff" do
    describe "channels" do
      for_  [ "unbounded" /\ TestUnbounded /\ P.unbounded
            , "new" /\ TestNew /\ P.new
            ] \(label /\ bufferType /\ buffer) -> do
        describe label do
          it "should run forever" do
            chan <- P.spawn buffer
            fiber <- forkAff $ runEffect $ for (P.fromInput chan) (const $ pure unit)
            r <- sequential $ oneOf
                                [ parallel $ true  <$ delay (10.0 # Milliseconds)
                                , parallel $ false <$ joinFiber fiber
                                ]
            r `shouldEqual` true

          it "should stop running once sealed" do
            chan <- P.spawn buffer
            fiber <- forkAff $ runEffect $ for (P.fromInput chan) (const $ pure unit)
            P.seal chan
            r <- sequential $ oneOf
                                [ parallel $ false <$ delay (10.0 # Milliseconds)
                                , parallel $ true  <$ joinFiber fiber
                                ]
            r `shouldEqual` true

          it "should not block when sending" do
            chan <- P.spawn buffer
            flip shouldEqual true =<< P.send 1 chan
            flip shouldEqual true =<< P.send 2 chan
            P.seal chan
            flip shouldEqual false =<< P.send 3 chan

          when (bufferType == TestUnbounded) do
            it "should produce values in order" do
              chan <- P.spawn buffer
              flip shouldEqual true =<< P.send 1 chan
              flip shouldEqual true =<< P.send 2 chan
              ref <- liftEff $ newRef []
              runEffect $ for (P.fromInput chan) \v -> do
                liftEff $ modifyRef ref (flip Array.snoc v)
                when (v == 2) do
                  liftAff $ P.seal chan
              flip shouldEqual [1, 2] =<< liftEff (readRef ref)

