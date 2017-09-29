module Test.Main where

import Prelude
import Data.Array ((..))
import Data.Array as Array
import Data.Time.Duration (Milliseconds(..))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, modifyRef)
import Control.Monad.Aff (forkAff, delay)
import Pipes.Aff as P
import Pipes.Aff (Buffer, unbounded)
import Pipes.Prelude hiding (show, map)
import Pipes.Core
import Pipes hiding (discard)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)

main :: Eff _ Unit
main = run [consoleReporter] do
  describe "purescript-spec" do
    it "can pipe values using `Pipes.spawn`" do
      channel <- P.spawn unbounded
      void $ forkAff $
        let loop n = do
              delay (1.0 # Milliseconds)
              void $ P.send ("n: " <> show n) channel
              if n < 10
                then loop (n + 1)
                else P.seal channel
         in loop 1

      r <- liftEff $ newRef []
      runEffect $ for (P.fromInput channel) \v -> do
        liftEff $ modifyRef r (_ `Array.snoc` v)
      xs <- liftEff $ readRef r
      xs `shouldEqual` ((("n: " <> _) <<< show) <$> (1..10))
