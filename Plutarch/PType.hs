{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module Plutarch.PType (
  pHs_inverse,
  PGeneric,
  PCode,
  PDatatypeInfoOf,
  pgto,
  pgfrom,
  PTypeF (MkPTypeF'),
  MkPTypeF,
  PType,
  PPType (PPType),
  Pf' (..),
  PfC,
  PHs,
  UnPHs,
  PHs' (..),
  PHsEf,
  PHsW,
  type (/$),
  convertPfC,
) where

import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy (Proxy))
import GHC.Generics (Generic)
import Generics.SOP (I, SListI2, SOP, Top)
import Generics.SOP.GGP (GCode, GDatatypeInfo, GDatatypeInfoOf, GFrom, GTo)
import Plutarch.Internal.CoerceTo (CoerceTo)
import Plutarch.Internal.Witness (witness)
import Plutarch.Reduce (NoReduce, Reduce)
import Unsafe.Coerce (unsafeCoerce)
import Data.Type.Equality ((:~:)(Refl))

type APC = forall (a :: PType). PHs a -> Constraint
type AC = forall (a :: Type). a -> Constraint

{- | What is a PType? It's a type that represents higher HKDs,
 in the sense that their elements are applied to a type-level function,
 but the core difference is that the following type is made legal:
 `data A f = A (Pf f A)` which is isomorphic to `data A f = A (f A)`.
 Simple HKDs don't allow this, as you'd have to do `data A f = A (f (A Identity))`
 or similar, which doesn't convey the same thing.
 This form of (higher) HKDs is useful for eDSLs, as you can replace the
 the fields with eDSL terms.
-}
data PTypeF = MkPTypeF'
  { _constraint :: AC
  , _concretise :: Conc
  }

-- | Higher HKD
type PType = PTypeF -> Type

type Conc = PType -> Type

newtype PPType (ef :: PTypeF) = PPType PType

type PHsEf = MkPTypeF' Top PHsW

type PHsW :: PType -> Type
newtype PHsW a = PHsW (NoReduce (PHs a)) deriving stock (Generic)

type PHs :: PType -> Type
type family PHs (a :: PType) = r | r -> a where
  PHs PPType = PType
  PHs a = a PHsEf

type UnPHs :: Type -> PType
type family UnPHs a where
  UnPHs PType = PPType
  UnPHs (a _) = a

pHs_inverse :: a :~: UnPHs (PHs a)
pHs_inverse = unsafeCoerce Refl

newtype PHs' a = PHs' (PHs a)

type family (/$) (f :: PTypeF) (x :: PType) :: Type where
  forall (_constraint :: AC) (concretise :: Conc) (x :: PType).
    (/$) (MkPTypeF' _constraint concretise) x =
      Reduce (concretise x)
infixr 0 /$

newtype Pf' ef a = Pf' (ef /$ a)

type family PfC (f :: PTypeF) :: PHs a -> Constraint where
  forall (constraint :: AC) (_concretise :: Conc).
    PfC (MkPTypeF' constraint _concretise) =
      constraint

data Dummy (a :: PType) deriving stock (Generic)

type UnDummy :: Type -> PType
type family UnDummy a where
  UnDummy (Dummy a) = a

type ToPType :: [Type] -> [PType]
type family ToPType as where
  ToPType '[] = '[]
  ToPType (a ': as) = UnDummy a ': ToPType as

type ToPType2 :: [[Type]] -> [[PType]]
type family ToPType2 as where
  ToPType2 '[] = '[]
  ToPType2 (a ': as) = ToPType a ': ToPType2 as

type DummyEf :: PTypeF
type DummyEf = MkPTypeF' Top Dummy

type family OpaqueEf :: PTypeF where

type family VerifyPCode'' (p :: PType) (a :: Type) :: Constraint where
  VerifyPCode'' p a = a ~ (OpaqueEf /$ p)

type family VerifyPCode' (ps :: [PType]) (as :: [Type]) :: Constraint where
  VerifyPCode' '[] '[] = ()
  VerifyPCode' (p ': ps) (a ': as) = (VerifyPCode'' p a, VerifyPCode' ps as)

-- Makes sure that user doesn't match on `PTypeF` passed in, because otherwise
-- `PCode` will return the wrong thing potentially.
type family VerifyPCode (pss :: [[PType]]) (ass :: [[Type]]) :: Constraint where
  VerifyPCode '[] '[] = ()
  VerifyPCode (ps ': pss) (as ': ass) = (VerifyPCode' ps as, VerifyPCode pss ass)

{- | NB: This doesn't work if the data type definition matches
 on the `ef` using a type family.
 You need to use `VerifyPCode` to make sure it's correct.
-}
type family PCode (a :: PType) :: [[PType]] where
  PCode a = ToPType2 (GCode (a DummyEf))

class
  ( Generic (a ef)
  , GFrom (a ef)
  , GTo (a ef)
  , GDatatypeInfo (a ef)
  , VerifyPCode (PCode a) (GCode (a OpaqueEf))
  , SListI2 (PCode a)
  , SListI2 (GCode (a ef))
  ) =>
  PGeneric' a ef
instance
  ( Generic (a ef)
  , GFrom (a ef)
  , GTo (a ef)
  , GDatatypeInfo (a ef)
  , VerifyPCode (PCode a) (GCode (a OpaqueEf))
  , SListI2 (PCode a)
  , SListI2 (GCode (a ef))
  ) =>
  PGeneric' a ef

type PGeneric :: PType -> Constraint
class (forall ef. PGeneric' a ef) => PGeneric a
instance (forall ef. PGeneric' a ef) => PGeneric a

{- | Does `unsafeCoerce` underneath the hood, but is a safe use of it.
 This and `pgto` could be implemented safely, but it's quite complex and not really worth it.
 We know this is correct because 'VerifyPCode' checks this exact claim, i.e.,
 every element of @GCode (a ef)@ is @ef /$ p@ where @p@ is from @PCode a@.
 This function is useful for operating over 'PType's generically.
-}
pgfrom :: forall a ef. PGeneric a => Proxy a -> Proxy ef -> SOP I (GCode (a ef)) -> SOP (Pf' ef) (PCode a)
pgfrom = let _ = witness (Proxy @(PGeneric a)) in \_ _ x -> unsafeCoerce x

-- | See 'pgto'.
pgto :: forall a ef. PGeneric a => Proxy a -> Proxy ef -> SOP (Pf' ef) (PCode a) -> SOP I (GCode (a ef))
pgto = let _ = witness (Proxy @(PGeneric a)) in \_ _ x -> unsafeCoerce x

type PDatatypeInfoOf a = GDatatypeInfoOf (a OpaqueEf)

type H0 :: Type -> PType
type family H0 a where
  H0 PType = PPType
  H0 (a _ef) = a

type H1 :: forall (a :: Type). a -> PHs (H0 a)
type family H1 (x :: a) where
  forall (x :: PType).
    H1 x =
      x
  forall (a :: PType) (_ef :: PTypeF) (x :: a _ef).
    H1 x =
      CoerceTo (PHs a) x -- need to show GHC that `a` can't be `PType` somehow.

type H2 :: APC -> AC
class apc (H1 x) => H2 (apc :: APC) (x :: a)
instance forall (apc :: APC) (a :: Type) (x :: a). apc (H1 x) => H2 (apc :: APC) (x :: a)

newtype Helper1 (apc :: APC) (x :: PHs a) b = Helper1 (apc (H1 x) => b)
newtype Helper2 (apc :: APC) (x :: PHs a) b = Helper2 {runHelper2 :: apc x => b}

-- What we really need to do here is an erased pattern match on `a`, to show
-- that no matter what `a` is, the following is correct.
-- GHC unfortunately supports no such thing, so we use `unsafeCoerce`.
convertPfC :: forall (apc :: APC) a (x :: PHs a) b. apc x => Proxy apc -> Proxy x -> (apc (H1 x) => b) -> b
convertPfC _ _ f = let _ = Helper2 in runHelper2 (unsafeCoerce (Helper1 @a @apc @x @b f) :: Helper2 apc x b)

type MkPTypeF :: APC -> ((PTypeF -> Type) -> Type) -> PTypeF
type family MkPTypeF constraint concretise where
  forall (constraint :: APC) (concretise :: PType -> Type).
    MkPTypeF constraint concretise =
      MkPTypeF' (H2 constraint) concretise
