module Test.Main where

import Prelude
import Data.Array ((..))
import Data.Array as Array
import Data.Time.Duration (Milliseconds(..))
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, modifyRef)
import Control.Monad.Aff.Console (log)
import Control.Monad.Aff (launchAff, forkAff, delay)
import Pipes.Aff as Pipes
import Pipes.Aff (Buffer, unbounded)
import Pipes.Prelude hiding (show, map)
import Pipes.Core
import Pipes hiding (discard)
import Test.Spec (pending, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (RunnerEffects, run)

main :: Eff _ Unit
main = run [consoleReporter] do
  describe "purescript-spec" do
    it "can pipe values using `Pipes.spawn`" do
      { input, output, seal } <- Pipes.spawn unbounded
      void $ forkAff $
        let loop n = do
              delay (1.0 # Milliseconds)
              void $ Pipes.send output $ "n: " <> show n
              if n < 10
                then loop (n + 1)
                else seal
         in loop 1

      r <- liftEff $ newRef []
      runEffect $ for (Pipes.fromInput input) \v -> do
        liftEff $ modifyRef r (_ `Array.snoc` v)
      xs <- liftEff $ readRef r
      xs `shouldEqual` ((("n: " <> _) <<< show) <$> (1..10))
