module Test.Main where

import Prelude
import Data.Time.Duration (Milliseconds(..))
import Control.Monad.Trans.Class (lift)
import Control.Monad.Eff (Eff)
import Control.Monad.Aff.Console (log)
import Control.Monad.Aff (launchAff, forkAff, delay)

import Pipes.Aff as Pipes
import Pipes.Aff (Buffer(..))
import Pipes.Prelude
import Pipes.Core
import Pipes hiding (discard)

main :: forall e. Eff _ Unit
main = void $ launchAff do
  { input, output, seal } <- Pipes.spawn Unbounded
  _ <- forkAff do
    let loop = do
          delay (100.0 # Milliseconds)
          Pipes.send output "hi there"
    loop
  runEffect $ for (Pipes.fromInput input) $ lift <<< log
