module Control.Promise (fromAff, toAff, toAffE, Promise()) where

import Prelude

import Control.Alt ((<|>))
import Control.Monad.Aff (Aff, makeAff, runAff_)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Eff.Uncurried (EffFn1, mkEffFn1)
import Control.Monad.Except (runExcept)
import Data.Either (Either(..), either)
import Data.Foreign (Foreign, readString, unsafeReadTagged)
import Data.Monoid (mempty)

-- | Type of JavaScript Promises (with particular return type)
-- | Effects are not traced in the Promise type, as they form part of the Eff that
-- | results in the promise.
foreign import data Promise :: Type -> Type

foreign import promise :: forall eff a b.
  ((a -> Eff eff Unit) -> (b -> Eff eff Unit) -> Eff eff Unit) -> Eff eff (Promise a)
foreign import thenImpl :: forall a b e.
  Promise a -> (EffFn1 e Foreign b) -> (EffFn1 e a b) -> Eff e Unit

-- | Convert an Aff into a Promise.
fromAff :: forall eff a. Aff eff a -> Eff eff (Promise a)
fromAff aff = promise (\succ err -> runAff_ (either err succ) aff)

coerce :: Foreign -> Error
coerce fn =
  either (\_ -> error "Promise failed, couldn't extract JS Error or String")
         id
         (runExcept ((unsafeReadTagged "Error" fn) <|> (error <$> readString fn)))

-- | Convert a Promise into an Aff.
-- | When the promise rejects, we attempt to
-- | coerce the error value into an actual JavaScript Error object. We can do this
-- | with Error objects or Strings. Anything else gets a "dummy" Error object.
toAff :: forall eff a. Promise a -> Aff eff a
toAff p = makeAff
  (\cb -> mempty <$ thenImpl
    p
    (mkEffFn1 $ cb <<< Left <<< coerce)
    (mkEffFn1 $ cb <<< Right))

-- | Utility to convert an Eff returning a Promise into an Aff (i.e. the inverse of fromAff)
toAffE :: forall eff a. Eff eff (Promise a) -> Aff eff a
toAffE f = liftEff f >>= toAff