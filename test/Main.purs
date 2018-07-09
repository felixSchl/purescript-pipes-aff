module Test.Main where

import Prelude

import Control.Parallel (parallel, sequential)
import Pipes.Core (runEffect)
import Effect.Aff (delay, forkAff, joinFiber)
import Effect.Aff.Class (liftAff)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Data.Array as Array
import Data.Foldable (for_, oneOf)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Pipes (for)
import Pipes.Aff as P
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run', defaultConfig)

data TestBufferType = TestUnbounded | TestNew
derive instance eqTestBuffer :: Eq TestBufferType

main :: Effect Unit
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
              ref <- liftEffect $ Ref.new []
              runEffect $ for (P.fromInput chan) \v -> do
                _ <- liftEffect $ Ref.modify (flip Array.snoc v) ref
                when (v == 2) do
                  liftAff $ P.seal chan
              flip shouldEqual [1, 2] =<< liftEffect (Ref.read ref)

