module Test.Main where

import Data.Maybe
import Pipes.Core
import Prelude

import Control.Monad.Aff (forkAff, delay)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, modifyRef)
import Control.Monad.Rec.Class (tailRecM, Step(..))
import Data.Array ((..))
import Data.Array as Array
import Data.Time.Duration (Milliseconds(..))
import Debug.Trace (traceAnyA)
import Pipes hiding (discard)
import Pipes.Aff (Buffer, unbounded)
import Pipes.Aff as P
import Pipes.Prelude hiding (show,map)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run', defaultConfig)

main :: Eff _ Unit
main = run' (defaultConfig { timeout = Nothing }) [consoleReporter] do
  describe "pipes-aff" do
    describe "channel (unbounded)" do
      it "can pipe values using `Pipes.spawn`" do
        channel <- P.spawn P.new

        -- let go n | n < 1000 = do
        --       delay (1.0 # Milliseconds)
        --       void $ P.send ("n: " <> show n) channel
        --       traceAnyA $ "I sent: " <> ("n: " <> show n)
        --       pure $ Loop (n + 1)
        --     go _ = pure (Done unit)
        -- void $ forkAff $ tailRecM go 1

        let loop n = do
              delay (1.0 # Milliseconds)
              void $ P.send ("n: " <> show n) channel
              if n < 1000000
                then loop (n + 1)
                else do
                    traceAnyA "sealing it!!!"
                    P.seal channel
        loop 1

        -- r <- liftEff $ newRef []
        runEffect $ for (P.fromInput channel) \v -> do
          liftAff $ delay $ 10.0 # Milliseconds

        liftAff $ delay $ 1000000.0 # Milliseconds
          -- liftEff $ modifyRef r (_ `Array.snoc` v)
        -- xs <- liftEff $ readRef r
        -- xs `shouldEqual` ((("n: " <> _) <<< show) <$> (1..10))
