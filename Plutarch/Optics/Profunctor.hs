{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module Plutarch.Optics.Profunctor where

import Plutarch.Core

class PProfunctor edsl p where
  pdimap ::
    (IsEType edsl c, IsEType edsl d) =>
    (a :--> b) edsl ->
    (c :--> d) edsl ->
    p b c ->
    p a d

class (PProfunctor edsl p, ESOP edsl) => PStrong edsl p where
  pfirst' ::
    (IsEType edsl a, IsEType edsl b, IsEType edsl c) =>
    p a b ->
    p (EPair a c) (EPair b c)
  pfirst' = pdimap @edsl pswap pswap . psecond' @edsl

  psecond' ::
    (IsEType edsl a, IsEType edsl b, IsEType edsl c) =>
    p a b ->
    p (EPair c a) (EPair c b)
  psecond' = pdimap @edsl pswap pswap . pfirst' @edsl
  {-# MINIMAL pfirst' | psecond' #-}

plmap ::
  (PProfunctor edsl p, IsEType edsl c) =>
  (a :--> b) edsl ->
  p b c ->
  p a c
plmap f = pdimap f id

prmap ::
  (PProfunctor edsl p, IsEType edsl b, IsEType edsl c) =>
  (b :--> c) edsl ->
  p a b ->
  p a c
prmap = pdimap id

newtype TermF edsl a b = TermF {unTermF :: Term edsl a -> Term edsl b}

instance PProfunctor edsl (TermF edsl) where
  pdimap ab cd (TermF bc) = TermF (cd . bc . ab)

pswap ::
  (ESOP edsl, IsEType edsl a, IsEType edsl b) =>
  (EPair a b :--> EPair b a) edsl
pswap tp = ematch tp \(EPair a b) -> econ $ EPair b a

class (PProfunctor edsl p, ESOP edsl) => PChoice edsl p where
  pleft' ::
    (IsEType edsl a, IsEType edsl b, IsEType edsl c) =>
    p a b ->
    p (EEither a c) (EEither b c)
  pleft' =
    pdimap
      @edsl
      (peither (econ . ERight) (econ . ELeft))
      (peither (econ . ERight) (econ . ELeft))
      . pright' @edsl

  pright' :: (IsEType edsl a, IsEType edsl b, IsEType edsl c) => p a b -> p (EEither c a) (EEither c b)
  pright' =
    pdimap
      @edsl
      (peither (econ . ERight) (econ . ELeft))
      (peither (econ . ERight) (econ . ELeft))
      . pleft' @edsl
  {-# MINIMAL pleft' | pright' #-}