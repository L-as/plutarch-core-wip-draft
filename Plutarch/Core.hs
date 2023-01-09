{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module Plutarch.Core (
  PDSL (..),
  PDSLKind (..),
  UnPDSLKind,
  Term (..),
  ClosedTerm,
  unTerm,
  PConcrete,
  PConcreteEf,
  IsPType (..),
  isPTypeQuantified,
  IsPTypeData (IsPTypeData),
  PConstructable (..),
  PConstructablePrim (..),
  PAp (..),
  PEmbeds (..),
  Compile,
  CompileTy,
  CompileAp,
  IsPTypePrim (..),
  withIsPType,
) where

import Data.Functor.Compose (Compose)
import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy (Proxy))
import GHC.Records (HasField (getField))
import GHC.Stack (HasCallStack)
import Plutarch.Internal.WithDictHack (unsafeWithDict)
import Plutarch.PType (
  MkPTypeF,
  PHs,
  PType,
  PTypeF,
 )
import Plutarch.Reduce (NoReduce)
import Plutarch.Repr (PIsRepr, PRepr, PReprC, PReprSort, prfrom, prto)

newtype PDSLKind = PDSLKind (PType -> Type)

type family UnPDSLKind (edsl :: PDSLKind) :: PType -> Type where
  UnPDSLKind ( 'PDSLKind edsl) = edsl

type NoTypeInfo :: forall k. PHs k -> Constraint
class NoTypeInfo a
instance NoTypeInfo a

class Monad (PEffect edsl) => PDSL (edsl :: PDSLKind) where
  data PEffect edsl :: Type -> Type
  data IsPTypePrimData edsl :: forall (a :: PType). PHs a -> Type

type IsPTypePrim :: PDSLKind -> forall (a :: PType). PHs a -> Constraint
class IsPTypePrim (edsl :: PDSLKind) (x :: PHs a) where
  isPTypePrim :: IsPTypePrimData edsl x

type role Term nominal nominal
newtype Term (edsl :: PDSLKind) (a :: PType) where
  Term :: UnPDSLKind edsl (PRepr a) -> Term edsl a

unTerm :: Term edsl a -> UnPDSLKind edsl (PRepr a)
unTerm (Term t) = t

type ClosedTerm (c :: PDSLKind -> Constraint) (a :: PType) = forall edsl. c edsl => Term edsl a

type IsPTypeData :: PDSLKind -> forall (a :: PType). PHs a -> Type
newtype IsPTypeData edsl x = IsPTypeData (IsPTypePrimData edsl (PRepr x))

type IsPType :: PDSLKind -> forall (a :: PType). PHs a -> Constraint
-- FIXME: remove GiveRepr superclass, should be unnecessary, maybe GHC bug?
class IsPType edsl (x :: PHs a) where
  isPType :: IsPTypeData edsl x
instance
  ( IsPTypePrim edsl (PRepr x)
  ) =>
  IsPType edsl (x :: PHs a)
  where
  isPType = IsPTypeData isPTypePrim

withIsPType :: forall edsl x a. IsPTypeData edsl x -> (IsPType edsl x => a) -> a
withIsPType x = unsafeWithDict (Proxy @(IsPType edsl x)) x

isPTypeQuantified ::
  forall edsl f y.
  (forall x. IsPType edsl x => IsPType edsl (f x)) =>
  Proxy edsl ->
  Proxy f ->
  IsPTypeData edsl y -> IsPTypeData edsl (f y)
isPTypeQuantified _ _ y = withIsPType y $ isPType @edsl @_ @(f y)

type PConcreteEf :: PDSLKind -> PTypeF
type PConcreteEf edsl = MkPTypeF (IsPType edsl) (Compose NoReduce (Term edsl))

type PConcrete :: PDSLKind -> PType -> Type
type PConcrete edsl a = a (PConcreteEf edsl)

class (PDSL edsl, IsPTypePrim edsl a) => PConstructablePrim edsl (a :: PType) where
  pconImpl :: HasCallStack => PConcrete edsl a -> UnPDSLKind edsl a
  pmatchImpl :: forall b. (HasCallStack, IsPType edsl b) => UnPDSLKind edsl a -> (PConcrete edsl a -> Term edsl b) -> Term edsl b
  pcaseImpl :: forall b. (HasCallStack, IsPType edsl b) => UnPDSLKind edsl a -> (PConcrete edsl a -> PEffect edsl (Term edsl b)) -> PEffect edsl (Term edsl b)

-- | The crux of what an eDSL is.
class IsPType edsl a => PConstructable edsl (a :: PType) where
  pcon :: HasCallStack => PConcrete edsl a -> Term edsl a
  pmatch ::
    forall b.
    (HasCallStack, IsPType edsl b) =>
    Term edsl a ->
    (PConcrete edsl a -> Term edsl b) ->
    Term edsl b
  pcase ::
    forall b.
    (HasCallStack, IsPType edsl b) =>
    Term edsl a ->
    (PConcrete edsl a -> PEffect edsl (Term edsl b)) ->
    PEffect edsl (Term edsl b)

instance (PIsRepr (PReprSort a), PReprC (PReprSort a) a, PConstructablePrim edsl (PRepr a)) => PConstructable edsl a where
  pcon x = Term $ pconImpl (prfrom x)
  pmatch (Term t) f = pmatchImpl t \x -> f (prto x)
  pcase (Term t) f = pcaseImpl t \x -> f (prto x)

class PDSL edsl => PAp (f :: Type -> Type) edsl where
  papr :: HasCallStack => f a -> Term edsl b -> Term edsl b
  papl :: HasCallStack => Term edsl a -> f b -> Term edsl a

class PAp m edsl => PEmbeds (m :: Type -> Type) edsl where
  pembed :: HasCallStack => m (Term edsl a) -> Term edsl a

type CompileTy variant output =
  forall a (x :: PHs a).
  Proxy x ->
  (forall edsl. variant edsl => IsPType edsl x) =>
  output

type CompileAp variant output =
  forall a m.
  Proxy a ->
  (HasCallStack, Applicative m, (forall edsl. variant edsl => IsPType edsl a)) =>
  (forall edsl. (variant edsl, PAp m edsl) => Term edsl a) ->
  m output

type Compile variant output =
  forall a m.
  Proxy a ->
  (HasCallStack, Monad m, (forall edsl. variant edsl => IsPType edsl a)) =>
  (forall edsl. (variant edsl, PEmbeds m edsl) => Term edsl a) ->
  m output

instance
  ( PConstructable e r
  , IsPType e a
  , HasField name (PConcrete e r) (Term e a)
  ) =>
  HasField name (Term e r) (Term e a)
  where
  getField x = pmatch x \x' -> getField @name x'
