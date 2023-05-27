{-# LANGUAGE UndecidableInstances #-}

module Plutarch.Internal.Utilities (
  insertPermutation,
  invPermutation,
  cmpListEqMod1,
  bringPermutation,
  transListEqMod1,
  idxPermutation,
  transPermutation,
  SimpleLanguage,
  InstSimpleLanguage,
  L (..),
  translateSimpleLanguage,
  extractSimpleLanguage,
  EmbedTwo,
  interpretTerm',
  interpretTerm,
  permuteTerm,
  permuteTerm',
  multicontract,
) where

import Data.Kind (Type)
import Data.SOP (K, NP)
import Data.Type.Equality ((:~:) (Refl))
import Plutarch.Core

insertPermutation :: ListEqMod1 xs xs' y -> Permutation xs ys -> Permutation xs' (y : ys)
insertPermutation ListEqMod1N perm = PermutationS ListEqMod1N perm
insertPermutation (ListEqMod1S idx) (PermutationS idx' rest) = PermutationS (ListEqMod1S idx') $ insertPermutation idx rest

invPermutation :: Permutation xs ys -> Permutation ys xs
invPermutation PermutationN = PermutationN
invPermutation (PermutationS idx rest) = insertPermutation idx $ invPermutation rest

cmpListEqMod1 ::
  ListEqMod1 new' new x ->
  ListEqMod1 tail new y ->
  ( forall tail'.
    Either
      (x :~: y, new' :~: tail)
      (ListEqMod1 tail' tail x, ListEqMod1 tail' new' y) ->
    r
  ) ->
  r
cmpListEqMod1 ListEqMod1N ListEqMod1N k = k (Left (Refl, Refl))
cmpListEqMod1 ListEqMod1N (ListEqMod1S idx) k = k (Right (ListEqMod1N, idx))
cmpListEqMod1 (ListEqMod1S idx) ListEqMod1N k = k (Right (idx, ListEqMod1N))
cmpListEqMod1 (ListEqMod1S idx) (ListEqMod1S idx') k = cmpListEqMod1 idx idx' \case
  Left (x, Refl) -> k (Left (x, Refl))
  Right (idx2, idx'2) -> k (Right (ListEqMod1S idx2, ListEqMod1S idx'2))

{-
cmpListEqMod1Idx ::
  ListEqMod1Idx xs xs' x ->
  ListEqMod1Idx xs' xs'' y ->
  ( forall tail'.
    Either
      (x :~: y, new' :~: tail)
      (ListEqMod1Idx tail' tail x, ListEqMod1Idx tail' new' y) ->
    r
  ) ->
  r
cmpListEqMod1Idx _ _ _ = undefined
cmpListEqMod1Idx ListEqMod1IdxN ListEqMod1IdxN k = k (Left (Refl, Refl))
cmpListEqMod1Idx ListEqMod1IdxN (ListEqMod1IdxS idx) k = k (Right (ListEqMod1IdxN, idx))
cmpListEqMod1Idx (ListEqMod1IdxS idx) ListEqMod1IdxN k = k (Right (idx, ListEqMod1IdxN))
cmpListEqMod1Idx (ListEqMod1IdxS idx) (ListEqMod1IdxS idx') k = cmpListEqMod1Idx idx idx' \case
  Left (x, Refl) -> k (Left (x, Refl))
  Right (idx2, idx'2) -> k (Right (ListEqMod1IdxS idx2, ListEqMod1IdxS idx'2))
-}

bringPermutation :: ListEqMod1 new' new x -> Permutation old new -> Permutation old (x : new')
bringPermutation ListEqMod1N x = x
bringPermutation idx (PermutationS idx' tail) =
  cmpListEqMod1 idx idx' \case
    Left (Refl, Refl) -> PermutationS ListEqMod1N tail
    Right (idx2, idx'2) ->
      PermutationS (ListEqMod1S idx'2) $
        bringPermutation idx2 $
          tail

transListEqMod1 ::
  ListEqMod1 xs ys x ->
  ListEqMod1 ys zs y ->
  (forall xs'. ListEqMod1 xs' zs x -> ListEqMod1 xs xs' y -> b) ->
  b
transListEqMod1 idx ListEqMod1N k = k (ListEqMod1S idx) ListEqMod1N
transListEqMod1 ListEqMod1N (ListEqMod1S idx) k = k ListEqMod1N idx
transListEqMod1 (ListEqMod1S idx) (ListEqMod1S idx') k =
  transListEqMod1 idx idx' \idx'' idx''' -> k (ListEqMod1S idx'') (ListEqMod1S idx''')

idxPermutation ::
  ListEqMod1 xs' xs x ->
  Permutation xs ys ->
  (forall ys'. ListEqMod1 ys' ys x -> Permutation xs' ys' -> b) ->
  b
idxPermutation ListEqMod1N (PermutationS idx rest) k = k idx rest
idxPermutation (ListEqMod1S idx) (PermutationS idx' rest) k =
  idxPermutation idx rest \idx'' rest' -> transListEqMod1 idx'' idx' \idx''' idx'''' ->
    k idx''' (PermutationS idx'''' rest')

transPermutation :: Permutation xs ys -> Permutation ys zs -> Permutation xs zs
transPermutation PermutationN PermutationN = PermutationN
transPermutation (PermutationS idx rest) perm =
  idxPermutation
    idx
    perm
    \idx' perm' -> PermutationS idx' (transPermutation rest perm')

interpret_to_LengthOfTwo :: InterpretAllIn xs ys idx -> (forall n. LengthOfTwo xs ys n -> r) -> r
interpret_to_LengthOfTwo (InterpretAllInN l) k = k l
interpret_to_LengthOfTwo (InterpretAllInS _ _ _ rest) k = interpret_to_LengthOfTwo rest k

transInterpretIn ::
  LengthOfTwo ys zs len -> InterpretIn xs ys x y -> InterpretIn ys zs y z -> InterpretIn xs zs x z
transInterpretIn =
  \shape xy yz -> InterpretIn \subls term ->
    helper shape subls \subls0 subls1 ->
      runInterpreter yz subls1 $ runInterpreter xy subls0 term
  where
    helper ::
      LengthOfTwo ys zs len ->
      SubLS ls0 ls2 xs zs ->
      (forall ls1. SubLS ls0 ls1 xs ys -> SubLS ls1 ls2 ys zs -> b) ->
      b
    helper (LengthOfTwoS shape) (SubLSSkip rest) k = helper shape rest \subls0 subls1 -> k (SubLSSkip subls0) (SubLSSkip subls1)
    helper (LengthOfTwoS shape) (SubLSSwap rest) k = helper shape rest \subls0 subls1 -> k (SubLSSwap subls0) (SubLSSwap subls1)
    helper LengthOfTwoN SubLSBase k = k SubLSBase SubLSBase

{-
data SameShapeWithSuffix :: [a] -> [a] -> [a] -> [a] -> Type where
  SameShapeWithSuffixN :: LengthOfTwo xs ys n -> SameShapeWithSuffix xs ys xs ys
  SameShapeWithSuffixS :: SameShapeWithSuffix xs ys (z : zs) (w : ws) -> SameShapeWithSuffix xs ys zs ws

sameShapeFromSuffix :: SameShapeWithSuffix xs ys zs ws -> (forall len. LengthOfTwo xs ys len -> r) -> r
sameShapeFromSuffix (SameShapeWithSuffixN shape) k = k shape
sameShapeFromSuffix (SameShapeWithSuffixS shape) k = sameShapeFromSuffix shape k
-}

removeFromLengthOfTwo ::
  ListEqMod1Idx xs' xs x idx ->
  ListEqMod1Idx ys' ys y idx ->
  LengthOfTwo xs ys len ->
  (forall len'. LengthOfTwo xs' ys' len' -> r) ->
  r
removeFromLengthOfTwo ListEqMod1IdxN ListEqMod1IdxN (LengthOfTwoS s) k = k s
removeFromLengthOfTwo (ListEqMod1IdxS idx) (ListEqMod1IdxS idx') (LengthOfTwoS s) k =
  removeFromLengthOfTwo idx idx' s (k . LengthOfTwoS)

listEqMod1IdxInjective :: ListEqMod1Idx xs' xs x idx -> ListEqMod1Idx ys' xs y idx -> '(xs', x) :~: '(ys', y)
listEqMod1IdxInjective ListEqMod1IdxN ListEqMod1IdxN = Refl
listEqMod1IdxInjective (ListEqMod1IdxS idx) (ListEqMod1IdxS idx') = case listEqMod1IdxInjective idx idx' of
  Refl -> Refl

transLengthOfTwo :: LengthOfTwo xs ys n -> LengthOfTwo ys zs n' -> (LengthOfTwo xs zs n, n :~: n')
transLengthOfTwo LengthOfTwoN LengthOfTwoN = (LengthOfTwoN, Refl)
transLengthOfTwo (LengthOfTwoS l) (LengthOfTwoS l') =
  case transLengthOfTwo l l' of (length, Refl) -> (LengthOfTwoS length, Refl)

lengthOfTwo_add_ListEqMod1 :: ListEqMod1 ys ys' y -> LengthOfTwo xs ys len -> LengthOfTwo (x : xs) ys' (S len)
lengthOfTwo_add_ListEqMod1 ListEqMod1N l = LengthOfTwoS l
lengthOfTwo_add_ListEqMod1 (ListEqMod1S idx) (LengthOfTwoS l) = LengthOfTwoS $ lengthOfTwo_add_ListEqMod1 idx l

lengthOfTwo_add_ListEqMod1_both ::
  ListEqMod1 xs xs' x ->
  ListEqMod1 ys ys' y ->
  LengthOfTwo xs ys len ->
  LengthOfTwo xs' ys' (S len)
lengthOfTwo_add_ListEqMod1_both idx idx' len =
  case flipLengthOfTwo $ lengthOfTwo_add_ListEqMod1 idx' len of
    LengthOfTwoS len' -> flipLengthOfTwo $ lengthOfTwo_add_ListEqMod1 idx len'

permutation_to_LengthOfTwo :: Permutation xs ys -> (forall len. LengthOfTwo xs ys len -> r) -> r
permutation_to_LengthOfTwo PermutationN k = k LengthOfTwoN
permutation_to_LengthOfTwo (PermutationS idx perm) k =
  permutation_to_LengthOfTwo perm \len -> k (lengthOfTwo_add_ListEqMod1 idx len)

transInterpret :: Interpret xs ys -> Interpret ys zs -> Interpret xs zs
transInterpret = go
  where
    go ::
      InterpretAllIn xs ys idx ->
      InterpretAllIn ys zs idx ->
      InterpretAllIn xs zs idx
    go (InterpretAllInN length) (InterpretAllInN length') = InterpretAllInN $ fst $ transLengthOfTwo length length'
    go (InterpretAllInN length) yzs = interpret_to_LengthOfTwo yzs \length' -> InterpretAllInN $ fst $ transLengthOfTwo length length'
    go xys (InterpretAllInN length) =
      interpret_to_LengthOfTwo xys \length' -> case transLengthOfTwo length' length of
        (length, Refl) -> InterpretAllInN length
    go (InterpretAllInS lidx lidx' xy xys) (InterpretAllInS ridx ridx' yz yzs) =
      case listEqMod1IdxInjective lidx' ridx of
        Refl ->
          InterpretAllInS
            lidx
            ridx'
            (interpret_to_LengthOfTwo yzs \len' -> removeFromLengthOfTwo lidx' ridx' len' \shape -> transInterpretIn shape xy yz)
            $ go xys yzs

data InterpretIdxs :: [Language] -> [Language] -> [Nat] -> Type where
  InterpretIdxsN :: LengthOfTwo ls0 ls1 len -> InterpretIdxs ls0 ls1 '[]
  InterpretIdxsS ::
    ListEqMod1Idx ls0' ls0 l idx ->
    ListEqMod1Idx ls1' ls1 l' idx ->
    InterpretIn ls0' ls1' l l' ->
    InterpretIdxs ls0 ls1 idxs ->
    InterpretIdxs ls0 ls1 (idx : idxs)

data Ascending :: Nat -> [Nat] -> Type where
  AscendingN :: Ascending n '[]
  AscendingS :: Ascending (S n) ns -> Ascending n (S n : ns)

data Undefined

makeUnIdxed :: Undefined -> InterpretIdxs ls0 ls0' idxs -> InterpretAllIn ls1 ls1' idx
makeUnIdxed = undefined

makeIdxed ::
  Undefined ->
  InterpretAllIn ls ls' idx ->
  InterpretIdxs ls ls' idxs
makeIdxed = undefined

-- transferPermutation :: LengthOfTwo xs zs len -> Permutation xs ys -> (forall ws. Permutation zs ws -> r) -> r
-- transferPermutation _ _ _ = undefined

-- If we can interpret from ys to zs,
-- but ys is a permutation of xs,
-- then it follows that we can also interpret  from xs to zs.
-- An interpretation is a list of interpreters,
-- for each interpreter in the list, we must switch its
-- position in the list, in addition to permuting its input
-- and output since the interpreter expected the languages ys
-- while we are giving it xs, and the output must be ws,
-- which is a permutation of zs.
--
-- Implementation:
-- The permutation is a list of indices,
-- which can be visualised as bijective arrows between elements of
-- xs and ys.
-- We must follow each arrow, such that the interpreter at the end of
-- each arrow is put at the position noted by the beginning of the arrow.
-- We can understand this as looking up an index in the list of interpreters.
-- The interpreter has a shape that is incompatible, it is expecting a term
-- with languages ys, when in fact it receives xs, a permutation of ys.
--
-- If you squint enough, this function is similar to transPermutation.
--
-- We start with a InterpretAllIn, which we then turn into a
-- InterpretIdxs _ _ _, that contains the same information.
-- This form is much more amenable to permutation.
-- We do two steps of recursion, one within the other.
-- We permute the InterpretIdxs such that the type-level indices
-- are permuted.
-- The goal is then to reorganise the language list such that
-- we can turn it back into another InterpretAllIn.
-- We do this by splitting up the work:
-- Given a list of indices idx : idxs, we first handle
-- the tail. If the tail is empty, it is a no-op, otherwise,
-- the tail must be reordered into an ascending order.

fja' ::
  SList ls0 ->
  Permutation2 xs ys zs ws ->
  SubLS ls0 ls1 xs zs ->
  ( forall ls0' ls1'.
    SubLS ls0' ls1' ys ws ->
    Permutation ls1' ls1 ->
    r
  ) ->
  r
fja' ls0 perm SubLSBase k = case perm of
  Permutation2N -> k SubLSBase (idPermutation ls0)

fja ::
  Permutation2 xs ys zs ws ->
  SubLS ls0 ls1 ys ws ->
  Term' x ls0 tag ->
  ( forall ls0' ls1'.
    SubLS ls0' ls1' xs zs ->
    Term' x ls0' tag ->
    Permutation ls1' ls1 ->
    r
  ) ->
  r
fja _ _ _ _ = undefined

permuteInterpretIn ::
  Permutation2 xs ys zs ws ->
  InterpretIn xs zs x y ->
  InterpretIn ys ws x y
permuteInterpretIn perm2 intr =
  InterpretIn \subls term ->
    fja perm2 subls term \subls' term' perm ->
      permuteTerm' perm $ runInterpreter intr subls' term'

data Permutation2 :: [a] -> [a] -> [b] -> [b] -> Type where
  Permutation2N :: Permutation2 '[] '[] '[] '[]
  Permutation2S ::
    ListEqMod1Idx ys ys' x idx ->
    ListEqMod1Idx ws ws' z idx ->
    Permutation2 xs ys zs ws ->
    Permutation2 (x : xs) ys' (z : zs) ws'

mkListEqMod1Idx :: ListEqMod1 xs xs' x -> (forall idx. ListEqMod1Idx xs xs' x idx -> r) -> r
mkListEqMod1Idx ListEqMod1N k = k ListEqMod1IdxN
mkListEqMod1Idx (ListEqMod1S x) k = mkListEqMod1Idx x \y -> k (ListEqMod1IdxS y)

unListEqMod1Idx :: ListEqMod1Idx xs xs' x idx -> ListEqMod1 xs xs' x
unListEqMod1Idx ListEqMod1IdxN = ListEqMod1N
unListEqMod1Idx (ListEqMod1IdxS idx) = ListEqMod1S $ unListEqMod1Idx idx

flipLengthOfTwo :: LengthOfTwo xs ys len -> LengthOfTwo ys xs len
flipLengthOfTwo LengthOfTwoN = LengthOfTwoN
flipLengthOfTwo (LengthOfTwoS len) = LengthOfTwoS $ flipLengthOfTwo len

transferListEqMod1Idx ::
  LengthOfTwo xs ys len ->
  ListEqMod1Idx xs xs' x idx ->
  (forall ys'. ListEqMod1Idx ys ys' y idx -> r) ->
  r
transferListEqMod1Idx _ ListEqMod1IdxN k = k ListEqMod1IdxN
transferListEqMod1Idx (LengthOfTwoS len) (ListEqMod1IdxS idx) k =
  transferListEqMod1Idx len idx (k . ListEqMod1IdxS)

permutation_to_Permutation2' ::
  LengthOfTwo xs zs len ->
  Permutation xs ys ->
  (forall ws. Permutation2 xs ys zs ws -> LengthOfTwo ys ws len -> r) ->
  r
permutation_to_Permutation2' LengthOfTwoN PermutationN k = k Permutation2N LengthOfTwoN
permutation_to_Permutation2' (LengthOfTwoS len) (PermutationS idx perm) k =
  permutation_to_Permutation2' len perm \perm' len' ->
    mkListEqMod1Idx idx \idx' ->
      transferListEqMod1Idx len' idx' \idx'' ->
        k
          (Permutation2S idx' idx'' perm')
          (lengthOfTwo_add_ListEqMod1_both (unListEqMod1Idx idx') (unListEqMod1Idx idx'') len')

permutation_to_Permutation2 ::
  LengthOfTwo xs zs len ->
  Permutation xs ys ->
  (forall ws. Permutation2 xs ys zs ws -> r) ->
  r
permutation_to_Permutation2 len perm k = permutation_to_Permutation2' len perm \perm' _ -> k perm'

permutation2_to_Permutation :: Permutation2 xs ys zs ws -> (Permutation xs ys, Permutation zs ws)
permutation2_to_Permutation Permutation2N = (PermutationN, PermutationN)
permutation2_to_Permutation (Permutation2S idx idx' perm2) =
  case permutation2_to_Permutation perm2 of
    (perm, perm') -> (PermutationS (unListEqMod1Idx idx) perm, PermutationS (unListEqMod1Idx idx') perm')

flipListEqMod1 ::
  ListEqMod1 xs ys x ->
  ListEqMod1 ys zs y ->
  (forall ws. ListEqMod1 xs ws y -> ListEqMod1 ws zs x -> r) ->
  r
flipListEqMod1 idx ListEqMod1N k = k ListEqMod1N (ListEqMod1S idx)
flipListEqMod1 ListEqMod1N (ListEqMod1S idx) k = k idx ListEqMod1N
flipListEqMod1 (ListEqMod1S idx) (ListEqMod1S idx') k =
  flipListEqMod1 idx idx' \idx'' idx''' -> k (ListEqMod1S idx'') (ListEqMod1S idx''')

remove_from_Permutation ::
  ListEqMod1 xs xs' x ->
  Permutation xs' ys' ->
  (forall ys. Permutation xs ys -> ListEqMod1 ys ys' x -> r) ->
  r
remove_from_Permutation ListEqMod1N (PermutationS idx perm) k = k perm idx
remove_from_Permutation (ListEqMod1S idx0) (PermutationS idx1 perm) k =
  remove_from_Permutation idx0 perm \perm' idx2 ->
    flipListEqMod1 idx2 idx1 \idx1' idx2' ->
      k (PermutationS idx1' perm') idx2'

flip2ListEqMod1Idx ::
  ListEqMod1Idx xs ys x idx ->
  ListEqMod1Idx ys zs y idx' ->
  ListEqMod1Idx xs' ys' x' idx ->
  ListEqMod1Idx ys' zs' y' idx' ->
  ( forall ws ws' idx0 idx'0.
    ListEqMod1Idx xs ws y idx0 ->
    ListEqMod1Idx ws zs x idx'0 ->
    ListEqMod1Idx xs' ws' y' idx0 ->
    ListEqMod1Idx ws' zs' x' idx'0 ->
    r
  ) ->
  r
flip2ListEqMod1Idx idx ListEqMod1IdxN idx' ListEqMod1IdxN k =
  k
    ListEqMod1IdxN
    (ListEqMod1IdxS idx)
    ListEqMod1IdxN
    (ListEqMod1IdxS idx')
flip2ListEqMod1Idx ListEqMod1IdxN (ListEqMod1IdxS idx) ListEqMod1IdxN (ListEqMod1IdxS idx') k =
  k idx ListEqMod1IdxN idx' ListEqMod1IdxN
flip2ListEqMod1Idx (ListEqMod1IdxS idx0) (ListEqMod1IdxS idx1) (ListEqMod1IdxS idx2) (ListEqMod1IdxS idx3) k =
  flip2ListEqMod1Idx idx0 idx1 idx2 idx3 \idx0' idx1' idx2' idx3' ->
    k
      (ListEqMod1IdxS idx0')
      (ListEqMod1IdxS idx1')
      (ListEqMod1IdxS idx2')
      (ListEqMod1IdxS idx3')

remove_from_Permutation2 ::
  ListEqMod1Idx xs xs' x idx ->
  ListEqMod1Idx zs zs' z idx ->
  Permutation2 xs' ys' zs' ws' ->
  (forall ys ws idx'. Permutation2 xs ys zs ws -> ListEqMod1Idx ys ys' x idx' -> ListEqMod1Idx ws ws' z idx' -> r) ->
  r
remove_from_Permutation2 ListEqMod1IdxN ListEqMod1IdxN (Permutation2S idx idx' perm2) k = k perm2 idx idx'
remove_from_Permutation2 (ListEqMod1IdxS idx0) (ListEqMod1IdxS idx1) (Permutation2S idx2 idx3 perm2) k =
  remove_from_Permutation2 idx0 idx1 perm2 \perm2' idx4 idx5 ->
    flip2ListEqMod1Idx idx4 idx2 idx5 idx3 \idx2' idx4' idx3' idx5' ->
      k (Permutation2S idx2' idx3' perm2') idx4' idx5'

permuteInterpretIdxs' ::
  Permutation2 xs ys zs ws ->
  InterpretIdxs xs zs idxs ->
  (forall idxs'. InterpretIdxs ys ws idxs' -> r) ->
  r
permuteInterpretIdxs' perm2 (InterpretIdxsN l) k =
  let (perm, perm') = permutation2_to_Permutation perm2
   in permutation_to_LengthOfTwo (invPermutation perm) \l' ->
        permutation_to_LengthOfTwo perm' \l'' ->
          k
            (InterpretIdxsN $ fst $ transLengthOfTwo (fst $ transLengthOfTwo l' l) l'')
permuteInterpretIdxs' perm2 (InterpretIdxsS idx0 idx1 intr intrs) k =
  permuteInterpretIdxs' perm2 intrs \intrs' ->
    remove_from_Permutation2 idx0 idx1 perm2 \perm2' idx2 idx3 ->
      let intr' = permuteInterpretIn perm2' intr
       in k (InterpretIdxsS idx2 idx3 intr' intrs')

extractLength_from_InterpretIdxs :: InterpretIdxs xs ys idxs -> (forall len. LengthOfTwo xs ys len -> r) -> r
extractLength_from_InterpretIdxs (InterpretIdxsN len) k = k len
extractLength_from_InterpretIdxs (InterpretIdxsS _ _ _ intrs) k = extractLength_from_InterpretIdxs intrs k

permuteInterpretIdxs ::
  Permutation xs ys ->
  InterpretIdxs xs zs idxs ->
  (forall ws idxs'. InterpretIdxs ys ws idxs' -> Permutation ws zs -> r) ->
  r
permuteInterpretIdxs perm intrs k =
  extractLength_from_InterpretIdxs intrs \len ->
    permutation_to_Permutation2 len perm \perm2 ->
      permuteInterpretIdxs' perm2 intrs \intrs' -> k intrs' (invPermutation $ snd $ permutation2_to_Permutation perm2)

permuteInterpretation ::
  Permutation xs ys ->
  Interpret xs zs ->
  (forall ws. Interpret ys ws -> Permutation ws zs -> r) ->
  r
permuteInterpretation perm intrs k =
  permuteInterpretIdxs
    perm
    (makeIdxed undefined intrs)
    \intrs' perm' -> k (makeUnIdxed undefined intrs') perm'

swapInterpretPermutation ::
  Permutation xs ys ->
  Interpret ys zs ->
  (forall ws. Interpret xs ws -> Permutation ws zs -> r) ->
  r
swapInterpretPermutation perm intr k =
  permuteInterpretation
    (invPermutation perm)
    intr
    \intr' perm' -> k intr' perm'

permuteTerm' :: Permutation xs ys -> Term' l xs tag -> Term' l ys tag
permuteTerm' perm' (Term' node intrs perm) =
  Term' node intrs (transPermutation perm perm')

permuteTerm :: Permutation xs ys -> Term xs tag -> Term ys tag
permuteTerm perm' (Term (Term' node intrs perm) idx) =
  remove_from_Permutation idx perm' \perm'' idx' ->
    Term (Term' node intrs (transPermutation perm perm'')) idx'

interpretTerm' :: Interpret ls ls' -> Term' l ls tag -> Term' l ls' tag
interpretTerm' intrs' (Term' node intrs perm) =
  swapInterpretPermutation
    perm
    intrs'
    \intrs'' perm' -> Term' node (transInterpret intrs intrs'') perm'

eqListEqMod1Idx ::
  ListEqMod1Idx ls0 ls1 x idx ->
  ListEqMod1Idx ls0' ls1 y idx ->
  ('(ls0, x) :~: '(ls0', y))
eqListEqMod1Idx _ _ = undefined

data LTE :: Nat -> Nat -> Type where
  LTEN :: LTE x x
  LTES :: LTE (S x) y -> LTE x y

idxInterpret' ::
  LTE idx' idx ->
  ListEqMod1Idx ls0' ls0 l idx ->
  InterpretAllIn ls0 ls1 idx' ->
  (forall ls1' l'. ListEqMod1Idx ls1' ls1 l' idx -> InterpretIn ls0' ls1' l l' -> r) ->
  r
idxInterpret'
  LTEN
  idx
  (InterpretAllInS idx' idx'' intr _)
  k = case eqListEqMod1Idx idx idx' of
    Refl -> k idx'' intr
idxInterpret'
  (LTES lte)
  idx
  (InterpretAllInS _ _ _ intrs)
  k = idxInterpret' lte idx intrs k
idxInterpret' lte idx (InterpretAllInN len) _ = absurd lte idx len
  where
    absurd :: LTE idx' idx -> ListEqMod1Idx xs xs' x idx -> LengthOfTwo xs' ys idx' -> a
    absurd _ _ _ = error "FIXME"

data LTEInv :: Nat -> Nat -> Type where
  LTEInvN :: LTEInv x x
  LTEInvS :: LTEInv x y -> LTEInv x (S y)

lteInv_to_LTE :: LTEInv x y -> LTE x y
lteInv_to_LTE LTEInvN = LTEN
lteInv_to_LTE (LTEInvS lte) = step $ lteInv_to_LTE lte
  where
    step :: LTE x y -> LTE x (S y)
    step LTEN = LTES LTEN
    step (LTES lte) = LTES $ step lte

zero_LTEInv :: SNat x -> LTEInv N x
zero_LTEInv SN = LTEInvN
zero_LTEInv (SS x) = LTEInvS $ zero_LTEInv x

zero_LTE :: SNat x -> LTE N x
zero_LTE = lteInv_to_LTE . zero_LTEInv

idxInterpret ::
  ListEqMod1Idx ls0' ls0 l idx ->
  Interpret ls0 ls1 ->
  (forall ls1' l'. ListEqMod1Idx ls1' ls1 l' idx -> InterpretIn ls0' ls1' l l' -> r) ->
  r
idxInterpret idx intrs k = idxInterpret' (zero_LTE undefined) idx intrs k

idSubLS :: LengthOfTwo ls ls' len -> SubLS ls ls' ls ls'
idSubLS LengthOfTwoN = SubLSBase
idSubLS (LengthOfTwoS len) = SubLSSwap $ idSubLS len

interpretTerm :: Interpret ls ls' -> Term ls tag -> Term ls' tag
interpretTerm intrs (Term term idx) =
  mkListEqMod1Idx idx \idx' ->
    idxInterpret idx' intrs \idx'' intr ->
      interpret_to_LengthOfTwo intrs \len ->
        removeFromLengthOfTwo idx' idx'' len \len' ->
          Term (runInterpreter intr (idSubLS len') term) (unListEqMod1Idx idx'')

{-
interpretInOther :: InterpretIn xs ys x y -> InterpretIn zs ws x y
interpretInOther = undefined

extendInterpretOne :: Interpret '[x] '[y] -> Interpret (x : xs) (y : ys)
extendInterpretOne = undefined

interpretTwo :: forall x y z. InterpretIn '[x, y] '[x, z] y z -> Interpret '[x, y] '[x, z]
interpretTwo gi@(InterpretIn g) = Interpret $ InterpretAllInS (InterpretIn f) $ InterpretAllInS (InterpretIn g) InterpretAllInN where
  f :: SubLS ls0 ls1 '[x, y] '[x, z] (Just '(x, x)) -> Term' x ls0 tag -> Term' x ls1 tag
  f (SubLSExcept (SubLSSkip SubLSBase)) term = term
  f (SubLSExcept (SubLSSwap SubLSBase)) term = interpretTerm' (extendInterpretOne $ Interpret $ InterpretAllInS (interpretInOther gi) InterpretAllInN) term

data SamePrefix :: [a] -> [a] -> [a] -> [a] -> Type where
  SamePrefixN :: SamePrefix xs ys xs ys
  SamePrefixS :: SamePrefix xs ys zs ws -> SamePrefix (x : xs) (x : ys) zs ws

extendInterpretAllIn ::
  SamePrefix xs ys zs ws ->
  InterpretAllIn xs ys zs ws ->
  InterpretAllIn xs ys xs ys
extendInterpretAllIn SamePrefixN intrs = intrs
-}
{-
extendInterpretAllIn (SamePrefixS SamePrefixN) intrs = InterpretAllInS (InterpretIn intr) intrs where
  intr :: SubLS ls0 ls1 (x : zs) (x : ws) (Just '(x, x)) -> Term' x ls0 tag -> Term' x ls1 tag
  intr (SubLSExcept SubLSBase) (Term' node intrs perm) = Term' node intrs perm
  intr (SubLSExcept (SubLSSkip SubLSBase)) (Term' node intrs perm) = Term' node intrs perm
  intr (SubLSExcept (SubLSSwap SubLSBase)) t@(Term' node intrs perm) = _ -- Term' node _ _
-}

data Catenation xs ys zs where
  CatenationN :: Catenation '[] ys ys
  CatenationS :: Catenation xs ys zs -> Catenation (x : xs) ys (x : zs)

type SimpleLanguage = [Tag] -> Tag -> Type
data InstSimpleLanguage :: SimpleLanguage -> Language

-- FIXME: Generalise to arbitrary node arities
data instance L (InstSimpleLanguage l) ls tag where
  SimpleLanguageNode0 :: l '[] tag -> L (InstSimpleLanguage l) '[] tag
  SimpleLanguageNode1 :: l '[arg] tag -> Term ls arg -> L (InstSimpleLanguage l) ls tag
  SimpleLanguageNode2 :: l '[arg, arg'] tag -> Term ls arg -> Term ls' arg' -> Catenation ls ls' ls'' -> L (InstSimpleLanguage l) ls'' tag
  ContractSimpleLanguage :: Term (InstSimpleLanguage l : InstSimpleLanguage l : ls) tag -> L (InstSimpleLanguage l) ls tag
  ExpandSimpleLanguage :: Term ls tag -> L (InstSimpleLanguage l) ls tag

extractSimpleLanguage ::
  (l subnodes tag -> NP (K a) subnodes -> a) ->
  Term '[InstSimpleLanguage l] tag ->
  a
extractSimpleLanguage = undefined

translateSimpleLanguage ::
  (forall tag'. l '[] tag' -> (Term' l' '[] tag', a)) ->
  (forall ls' tag' arg. l '[arg] tag' -> Term ls' arg -> (Term' l' ls' tag', a)) ->
  (forall ls' ls'' ls''' tag' arg arg'. l '[arg, arg'] tag' -> Term ls' arg -> Term ls'' arg' -> Catenation ls' ls'' ls''' -> (Term' l' ls''' tag', a)) ->
  Term (InstSimpleLanguage l : ls) tag ->
  (Term (l' : ls) tag, Maybe a)
translateSimpleLanguage _ _ _ _ = undefined

data EmbedTwo lx ly :: Language
data instance L (EmbedTwo lx ly) ls tag where
  EmbedTwo :: Term (lx : ly : ls) tag -> L (EmbedTwo lx ly) ls tag

---- examples

{-
type PType = Type

data Expr :: PType -> Tag

data BoolsTag :: SimpleLanguage where
  And :: BoolsTag '[Expr Bool, Expr Bool] (Expr Bool)
  Not :: BoolsTag '[Expr Bool] (Expr Bool)
  BoolLit :: Bool -> BoolsTag '[] (Expr Bool)
type Bools = InstSimpleLanguage BoolsTag
-}

class CCatenation xs ys zs | xs ys -> zs where
  ccatenation :: Catenation xs ys zs

instance CCatenation '[] ys ys where
  ccatenation = CatenationN

instance CCatenation xs ys zs => CCatenation (x : xs) ys (x : zs) where
  ccatenation = CatenationS ccatenation

type family Append (xs :: [a]) (ys :: [a]) :: [a] where
  Append '[] ys = ys
  Append (x : xs) ys = x : Append xs ys

data SList :: [a] -> Type where
  SNil :: SList '[]
  SCons :: SList xs -> SList (x : xs)

termToSList :: Term ls tag -> SList ls
termToSList (Term (Term' _ _ perm) idx) = g idx $ f $ invPermutation perm
  where
    f :: Permutation xs ys -> SList xs
    f PermutationN = SNil
    f (PermutationS _ rest) = SCons $ f rest
    g :: ListEqMod1 xs ys x -> SList xs -> SList ys
    g ListEqMod1N s = SCons s
    g (ListEqMod1S x) (SCons s) = SCons $ g x s

idPermutation :: SList xs -> Permutation xs xs
idPermutation SNil = PermutationN
idPermutation (SCons xs) = PermutationS ListEqMod1N (idPermutation xs)

data IndexInto :: [a] -> Nat -> Type where
  IndexIntoN :: IndexInto (x : xs) N
  IndexIntoS :: IndexInto xs idx -> IndexInto (x : xs) (S idx)

data SuffixOf :: [a] -> [a] -> Nat -> Type where
  SuffixOfN :: SuffixOf xs xs N
  SuffixOfS :: SuffixOf xs (y : ys) idx -> SuffixOf xs ys (S idx)

data Add :: Nat -> Nat -> Nat -> Type where
  AddN :: Add N n n
  AddS :: Add n m o -> Add (S n) m (S o)

data SNat :: Nat -> Type where
  SN :: SNat N
  SS :: SNat n -> SNat (S n)

add_n_N_n :: SNat n -> Add n N n
add_n_N_n SN = AddN
add_n_N_n (SS n) = AddS $ add_n_N_n n

addInjective :: Add n m o -> Add n m o' -> o :~: o'
addInjective AddN AddN = Refl
addInjective (AddS x) (AddS y) = case addInjective x y of
  Refl -> Refl

undoAddSFlipped :: Add n (S m) o -> (forall o'. o :~: S o' -> Add n m o' -> r) -> r
undoAddSFlipped AddN k = k Refl AddN
undoAddSFlipped (AddS add) k = undoAddSFlipped add \Refl add' -> k Refl (AddS add')

addSFlipped' :: Add n m o -> Add n' m m' -> Add n' o o' -> Add n m' o'
addSFlipped' AddN x y = case addInjective x y of Refl -> AddN
addSFlipped' (AddS add) x y = undoAddSFlipped y \Refl y' -> AddS $ addSFlipped' add x y'

addSFlipped :: Add n m o -> Add n (S m) (S o)
addSFlipped a = addSFlipped' a (AddS AddN) (AddS AddN)

suffixOf_to_IndexInto' :: IndexInto ys idx -> SuffixOf xs ys idx' -> Add idx' idx idx'' -> IndexInto xs idx''
suffixOf_to_IndexInto' idx SuffixOfN AddN = idx
suffixOf_to_IndexInto' idx (SuffixOfS suffix) (AddS add) = suffixOf_to_IndexInto' (IndexIntoS idx) suffix (addSFlipped add)

-- Logically equal to `(-) 1`
suffixOf_to_IndexInto :: SuffixOf xs ys (S idx) -> IndexInto xs idx
suffixOf_to_IndexInto (SuffixOfS suffix) = suffixOf_to_IndexInto' IndexIntoN suffix (add_n_N_n $ suffixOf_to_SNat suffix)

suffixOf_to_SNat :: SuffixOf xs ys idx -> SNat idx
suffixOf_to_SNat SuffixOfN = SN
suffixOf_to_SNat (SuffixOfS x) = SS (suffixOf_to_SNat x)

{-
indexInto_to_ListEqMod1Idx_flipped :: IndexInto xs idx -> (forall xs' x. ListEqMod1Idx xs xs' x idx -> r) -> r
indexInto_to_ListEqMod1Idx_flipped IndexIntoN k = k ListEqMod1IdxN
indexInto_to_ListEqMod1Idx_flipped (IndexIntoS idx) k = indexInto_to_ListEqMod1Idx_flipped idx (k . ListEqMod1IdxS)
-}

indexInto_to_ListEqMod1Idx :: IndexInto xs idx -> (forall xs' x. ListEqMod1Idx xs' xs x idx -> r) -> r
indexInto_to_ListEqMod1Idx IndexIntoN k = k ListEqMod1IdxN
indexInto_to_ListEqMod1Idx (IndexIntoS idx) k = indexInto_to_ListEqMod1Idx idx (k . ListEqMod1IdxS)

suffixOf_to_ListEqMod1Idx :: SuffixOf xs ys (S idx) -> (forall xs' x. ListEqMod1Idx xs' xs x idx -> r) -> r
suffixOf_to_ListEqMod1Idx suffix k = indexInto_to_ListEqMod1Idx (suffixOf_to_IndexInto suffix) k

idInterpretation :: SList xs -> Interpret xs xs
idInterpretation = f SuffixOfN
  where
    f :: SuffixOf xs ys idx -> SList ys -> InterpretAllIn xs xs idx
    f _ SNil = InterpretAllInN undefined
    f suffix (SCons xs) =
      suffixOf_to_ListEqMod1Idx (SuffixOfS suffix) \idx ->
        InterpretAllInS idx idx g $ f (SuffixOfS suffix) xs
    g :: InterpretIn ls ls l l
    g = InterpretIn \subls x -> case i subls of Refl -> x
    i :: SubLS xs ys zs zs -> xs :~: ys
    i SubLSBase = Refl
    i (SubLSSkip rest) = case i rest of Refl -> Refl
    i (SubLSSwap rest) = case i rest of Refl -> Refl

{-
pnot :: Term ls0 (Expr Bool) -> Term (Bools : ls0) (Expr Bool)
pnot x = Term (Term' (SimpleLanguageNode (ContainsS (catenationInv slist) x ContainsN) Not) (idInterpretation slist) (idPermutation slist)) ListEqMod1N
  where
    slist = termToSList x
-}

data ElemOf :: [a] -> a -> Type where
  ElemOfN :: ElemOf (x : xs) x
  ElemOfS :: ElemOf xs x -> ElemOf (y : xs) x

newtype Contractible :: Language -> Type where
  Contractible :: (forall ls tag. Term (l : l : ls) tag -> L l ls tag) -> Contractible l

runContractible :: Contractible l -> Term (l : l : ls) tag -> L l ls tag
runContractible (Contractible f) = f

data MultiContractible :: [Language] -> [Language] -> Type where
  MultiContractibleBase :: MultiContractible '[] '[]
  MultiContractibleContract :: Contractible l -> ElemOf ls l -> MultiContractible ls ls' -> MultiContractible (l : ls) ls'
  MultiContractibleSkip :: MultiContractible ls ls' -> MultiContractible (l : ls) (l : ls')

contract :: Contractible l -> Term (l : l : ls) tag -> Term (l : ls) tag
contract c term = Term (Term' node intrs perm) ListEqMod1N
  where
    node = runContractible c term
    intrs = idInterpretation slist
    perm = idPermutation slist
    SCons (SCons slist) = termToSList term

bringTerm :: ListEqMod1 ls' ls l -> Term ls tag -> Term (l : ls') tag
bringTerm = undefined

unbringTerm :: ListEqMod1 ls' ls l -> Term (l : ls') tag -> Term ls tag
unbringTerm = undefined

contractThere' :: ListEqMod1 ls' ls l -> Contractible l -> Term (l : ls) tag -> Term (l : ls') tag
contractThere' idx c term = contract c $ bringTerm (ListEqMod1S idx) term

elemOf_to_listEqMod1 :: ElemOf xs x -> (forall xs'. ListEqMod1 xs' xs x -> r) -> r
elemOf_to_listEqMod1 ElemOfN k = k ListEqMod1N
elemOf_to_listEqMod1 (ElemOfS rest) k = elemOf_to_listEqMod1 rest (k . ListEqMod1S)

listEqMod1_to_elemOf :: ListEqMod1 xs' xs x -> ElemOf xs x
listEqMod1_to_elemOf ListEqMod1N = ElemOfN
listEqMod1_to_elemOf (ListEqMod1S x) = ElemOfS $ listEqMod1_to_elemOf x

contractThere :: ElemOf ls l -> Contractible l -> Term (l : ls) tag -> Term ls tag
contractThere idx c term = elemOf_to_listEqMod1 idx \idx' -> unbringTerm idx' $ contractThere' idx' c term

data ReverseCatenation :: [a] -> [a] -> [a] -> Type where
  ReverseCatenationN :: ReverseCatenation '[] ys ys
  ReverseCatenationS :: ReverseCatenation xs (x : ys) zs -> ReverseCatenation (x : xs) ys zs

{-
catenationToNilIsInput :: Catenation xs '[] ys -> xs :~: ys
catenationToNilIsInput CatenationN = Refl
catenationToNilIsInput (CatenationS rest) = case catenationToNilIsInput rest of Refl -> Refl
-}

reverseCatenationFunctional :: ReverseCatenation xs suffix ys -> ReverseCatenation xs suffix zs -> ys :~: zs
reverseCatenationFunctional ReverseCatenationN ReverseCatenationN = Refl
reverseCatenationFunctional (ReverseCatenationS ys) (ReverseCatenationS zs) =
  case reverseCatenationFunctional ys zs of Refl -> Refl

multicontract' ::
  ReverseCatenation prefix ls0 ls0' ->
  ReverseCatenation prefix ls1 ls1' ->
  MultiContractible ls0 ls1 ->
  Term ls0' tag ->
  Term ls1' tag
multicontract' cnx cny MultiContractibleBase term =
  case reverseCatenationFunctional cnx cny of Refl -> term
multicontract' cnx cny (MultiContractibleSkip rest) term =
  multicontract' (ReverseCatenationS cnx) (ReverseCatenationS cny) rest term
multicontract' cnx _cny (MultiContractibleContract c idx rest) term = finalterm
  where
    shifted = bringTerm (util cnx ListEqMod1N) term
    contracted = elemOf_to_listEqMod1 idx \idx' -> contractThere (listEqMod1_to_elemOf $ util cnx (ListEqMod1S idx')) c shifted
    finalterm = multicontract' undefined undefined rest contracted
    util :: ReverseCatenation xs ys zs -> ListEqMod1 ys' ys x -> ListEqMod1 zs' zs x
    util = undefined

multicontract :: MultiContractible ls ls' -> Term ls tag -> Term ls' tag
multicontract = multicontract' ReverseCatenationN ReverseCatenationN

-- contractThere _ c $ multicontract' _ _ rest term
-- multicontract' _ _ (MultiContractibleSkip rest) term = _

-- pand' :: Term ls0 (Expr Bool) -> Term ls1 (Expr Bool) -> Term (Bools : Append ls0 ls1) (Expr Bool)
-- pand' x y = Term (Term' (SimpleLanguageNode _ And) _ _) ListEqMod1N