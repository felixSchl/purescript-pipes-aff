module Test.Main where

import Data.Maybe
import Pipes.Core
import Prelude

import Control.Monad.Aff (forkAff, launchAff, delay)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, modifyRef)
import Control.Monad.Rec.Class (tailRecM, Step(..), forever)
import Data.Array ((..))
import Data.Array as Array
import Data.Time.Duration (Milliseconds(..))
import Pipes hiding (discard)
import Pipes.Aff (Buffer, unbounded)
import Pipes.Aff as P
import Pipes.Prelude hiding (show,map)

main :: Eff _ Unit
main = void $ launchAff do
        channel <- P.spawn P.new
        let loop n = do
              delay (1.0 # Milliseconds)
              void $ P.send ("n: " <> show n) channel
              if n < 1000000
                then loop (n + 1)
                else do
                    P.seal channel
        loop 1

        -- r <- liftEff $ newRef []
        runEffect $ for (P.fromInput channel) \v -> do
          liftAff $ delay $ 10.0 # Milliseconds

        liftAff $ delay $ 1000000.0 # Milliseconds
          -- liftEff $ modifyRef r (_ `Array.snoc` v)
        -- xs <- liftEff $ readRef r
        -- xs `shouldEqual` ((("n: " <> _) <<< show) <$> (1..10))
