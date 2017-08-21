module Test.Main where

import Prelude
import Data.Time.Duration (Milliseconds(..))
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Aff (launchAff, forkAff, delay)

import Pipes.Aff as Pipes
import Pipes.Aff (Buffer, unbounded)
import Pipes.Prelude hiding (show)
import Pipes.Core
import Pipes hiding (discard)

main :: forall e. Eff _ Unit
main = void $ launchAff do
  { input, output, seal } <- Pipes.spawn unbounded

  _ <- forkAff do
    let loop n = do
          delay (1.0 # Milliseconds)
          _ <- Pipes.send output $ "n: " <> show n
          when (n < 10) do
            loop (n + 1)
    loop 0

  delay (10.0 # Milliseconds)
  void $ forkAff $ runEffect $ for (Pipes.fromInput input) $ lift <<< log
