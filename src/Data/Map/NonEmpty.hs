{-# language InstanceSigs #-}
{-# language ScopedTypeVariables #-}
{-# language Trustworthy #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Map.NonEmpty
-- Copyright   :  (c) Christopher Davenport 2018
-- License     :  BSD-style
-- Maintainer  :  Chris@ChristopherDavenport.tech
-- Portability :  portable
--
-- = Description
--
-- An efficient implementation of non-empty maps from keys to values (dictionaries).
--
-- Since many function names (but not the type name) clash with
-- "Prelude" names, this module is usually imported @qualified@, e.g.
--
-- >  import Data.Map.NonEmpty (NonEmptyMap)
-- >  import qualified Data.Map.NonEmpty as NonEmptyMap
-----------------------------------------------------------------------------
module Data.Map.NonEmpty(
  NonEmptyMap(..) -- Generic Constructor
  -- * Construction
  , singleton -- :: (k, a) -> NonEmptyMap k v
  , fromList -- :: Ord k => [(k, a)] -> Maybe (NonEmptyMap k a)
  , fromListWith -- :: Ord k => (a -> a -> a) -> [(k, a)] -> Maybe (NonEmptyMap k a)
  , fromListWithKey -- :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Maybe (NonEmptyMap k a)
  , fromNonEmpty -- :: Ord k => NonEmpty (k, a) -> NonEmptyMap k a
  , fromNonEmptyWith -- :: Ord k => (t -> t -> t) -> NonEmpty (k, t) -> NonEmptyMap k t
  , fromNonEmptyWithKey -- :: Ord k => (k -> a -> a -> a) -> NonEmpty (k, a) -> NonEmptyMap k a
  -- * Insertion
  , insert -- :: Ord k => k -> a -> NonEmptyMap k a -> NonEmptyMap k a
  , insertWith -- :: Ord k => (a -> a -> a) -> k -> a -> NonEmptyMap k a -> NonEmptyMap k a
  , insertWithKey -- :: Ord k => (k -> a -> a -> a) -> k -> a -> NonEmptyMap k a -> NonEmptyMap k a
  , insertLookupWithKey -- :: Ord k => (k -> a -> a -> a) -> k -> a -> NonEmptyMap k a -> (Maybe a, NonEmptyMap k a)
  -- * Deletion/Update
  , delete -- :: Ord k => k -> NonEmptyMap k a -> Map.Map k a
  , adjust -- :: Ord k => (a -> a) -> k -> NonEmptyMap k a -> NonEmptyMap k a
  , update -- :: Ord k => (a -> Maybe a) -> k -> NonEmptyMap k a -> Map.Map k a
  , alter  -- :: Ord k => (Maybe a -> Maybe a) -> k -> NonEmptyMap k a -> Map.Map k a
  , alterF -- :: forall f k a. (Functor f, Ord k) => (Maybe a -> f (Maybe a)) -> k -> NonEmptyMap k a -> f (Map.Map k a)
  -- * Query
  , lookup -- :: Ord k => k -> NonEmptyMap k a -> Maybe a
  , (!?)   -- :: Ord k => NonEmptyMap k a -> k -> Maybe a
  , findWithDefault -- :: Ord k => a -> k -> NonEmptyMap k a -> a
  , member -- :: Ord k => k -> NonEmptyMap k a -> Bool
  , notMember -- :: Ord k => k -> NonEmptyMap k a -> Bool
  -- * Size
  , size -- :: NonEmptyMap k a -> In
  -- * Conversions
  , toList -- :: NonEmptyMap k a -> [(k, a)]
  , Data.Map.NonEmpty.toNonEmpty -- :: NonEmptyMap k a -> NonEmpty (k, a)
  , toMap -- :: Ord k => NonEmptyMap k a -> Map.Map k a
  -- * Map
  , map -- :: (t -> b) -> NonEmptyMap k t -> NonEmptyMap k b
  , mapWithKey -- :: (t -> b) -> NonEmptyMap k t -> NonEmptyMap k b
  , mapKeys -- :: Ord k => (t2 -> k) -> NonEmptyMap t2 t1 -> NonEmptyMap k t1
  , mapKeysWith -- :: Ord k => (t1 -> t1 -> t1) -> (t2 -> k) -> NonEmptyMap t2 t1 -> NonEmptyMap k t1
) where

import qualified Data.Map                   as Map
import Data.Maybe                           (fromMaybe, isJust)
import Data.Functor.Classes                 (Eq1, Eq2, liftEq2, liftEq
                                            , Ord1, Ord2, liftCompare2, liftCompare
                                            , Show1, Show2, liftShowsPrec2, showsUnaryWith, liftShowsPrec, liftShowList2
                                            , Read1, liftReadsPrec, readsData, readsUnaryWith, liftReadList)
import Data.Semigroup                        (Semigroup, (<>))
import Data.Semigroup.Foldable               (Foldable1(..))
import Data.List.NonEmpty                    (NonEmpty(..))
import qualified Data.List.NonEmpty         as NonEmptyList
import qualified Data.List                  as List

import Prelude                              hiding (lookup, map)


-- | A NonEmptyMap of keys k to values a
data NonEmptyMap k a = NonEmptyMap (k, a) (Map.Map k a)

-- Instances


{--------------------------------------------------------------------
  Eq
--------------------------------------------------------------------}
instance Eq2 NonEmptyMap where
  liftEq2 :: (k -> l -> Bool) -> (m -> n -> Bool) -> NonEmptyMap k m -> NonEmptyMap l n -> Bool
  liftEq2 eqk eqa nem nen =
    size nen == size nen && liftEq (liftEq2 eqk eqa) (toList nem) (toList nen)

instance Eq k => Eq1 (NonEmptyMap k) where
  liftEq = liftEq2 (==)

{--------------------------------------------------------------------
  Ord
--------------------------------------------------------------------}
instance Ord2 NonEmptyMap where
  liftCompare2 cmpk cmpv m n =
    liftCompare (liftCompare2 cmpk cmpv) (toList m) (toList n)

instance Ord k => Ord1 (NonEmptyMap k) where
  liftCompare = liftCompare2 compare

{--------------------------------------------------------------------
  Show
--------------------------------------------------------------------}
instance Show2 NonEmptyMap where
  liftShowsPrec2 spk slk spv slv d m =
    showsUnaryWith (liftShowsPrec sp sl) "fromList" d (toList m)
    where
      sp = liftShowsPrec2 spk slk spv slv
      sl = liftShowList2 spk slk spv slv

instance Show k => Show1 (NonEmptyMap k) where
  liftShowsPrec = liftShowsPrec2 showsPrec showList

instance (Show k, Show a) => Show (NonEmptyMap k a) where
  showsPrec d m  = showParen (d > 10) $
    showString "fromList " . shows (toList m)

{--------------------------------------------------------------------
  Functor
--------------------------------------------------------------------}
instance Functor (NonEmptyMap k) where
  fmap :: (a -> b) -> NonEmptyMap k a -> NonEmptyMap k b
  fmap f (NonEmptyMap (k, v) map) =  NonEmptyMap (k, f v) (fmap f map)

{--------------------------------------------------------------------
  Foldable
--------------------------------------------------------------------}
instance Foldable (NonEmptyMap k) where
  foldr :: (a -> b -> b) -> b -> NonEmptyMap k a -> b
  foldr f b (NonEmptyMap (k, a) m) = Map.foldr f (f a b) m

instance Foldable1 (NonEmptyMap k) where
  foldMap1 :: Semigroup m => (a -> m) -> NonEmptyMap k a -> m
  foldMap1 f (NonEmptyMap (k, a) m) = Map.foldr ((<>) . f) (f a) m

-- Construction
singleton :: (k, a) -> NonEmptyMap k a
singleton tup = NonEmptyMap tup Map.empty

fromList :: Ord k => [(k, a)] -> Maybe (NonEmptyMap k a)
fromList []       = Nothing
fromList (x : xa) = Just $ NonEmptyMap x (Map.fromList xa)

fromNonEmpty :: Ord k => NonEmpty (k, a) -> NonEmptyMap k a
fromNonEmpty nel = NonEmptyMap (NonEmptyList.head nel) (Map.fromList (NonEmptyList.tail nel))

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Maybe (NonEmptyMap k a)
fromListWithKey _ [] = Nothing
fromListWithKey f (x:xs) = Just $ foldlStrict ins (NonEmptyMap (fst x, snd x) Map.empty) xs
  where
    ins t (k, v) = insertWithKey f k v t

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Maybe (NonEmptyMap k a)
fromListWith f xs = fromListWithKey (\_ x y -> f x y) xs

fromNonEmptyWithKey :: Ord k => (k -> a -> a -> a) -> NonEmpty (k, a) -> NonEmptyMap k a
fromNonEmptyWithKey f (x :| xs) = foldlStrict ins (NonEmptyMap x Map.empty) xs
  where
    ins t (k, v) = insertWithKey f k v t

fromNonEmptyWith :: Ord k => (t -> t -> t) -> NonEmpty (k, t) -> NonEmptyMap k t
fromNonEmptyWith f xs = fromNonEmptyWithKey (\_ x y -> f x y) xs

{--------------------------------------------------------------------
  Insertion
--------------------------------------------------------------------}

insert :: Ord k => k -> a -> NonEmptyMap k a -> NonEmptyMap k a
insert = insertWith const

insertWith :: Ord k => (a -> a -> a) -> k -> a -> NonEmptyMap k a -> NonEmptyMap k a
insertWith f key value (NonEmptyMap (k, a) m) | key == k  = NonEmptyMap (key, f value a) m
insertWith f key value (NonEmptyMap (k, a) m)             = NonEmptyMap (k, a) (Map.insertWith f key value m)

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> NonEmptyMap k a -> NonEmptyMap k a
insertWithKey f key value (NonEmptyMap (k, a) m) =
  if k == key then NonEmptyMap (key, f key value a) m
  else NonEmptyMap (k, a) (Map.insertWithKey f key value m)

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> NonEmptyMap k a -> (Maybe a, NonEmptyMap k a)
insertLookupWithKey f key value (NonEmptyMap (k, a) m) =
  if k == key then (Just a, NonEmptyMap(key, f key value a) m)
  else fmap (NonEmptyMap (k, a)) (Map.insertLookupWithKey f key value m)

{--------------------------------------------------------------------
  Deletion/Update
--------------------------------------------------------------------}
delete :: Ord k => k -> NonEmptyMap k a -> Map.Map k a
delete key (NonEmptyMap (k, a) m) | key == k  = m
delete key (NonEmptyMap (k, a) m)             = Map.insert k a (Map.delete k m)

adjust :: Ord k => (a -> a) -> k -> NonEmptyMap k a -> NonEmptyMap k a
adjust f key (NonEmptyMap (k, a) m) | key == k  = NonEmptyMap (key, f a) m
adjust f key (NonEmptyMap (k, a) m)             = NonEmptyMap (k, a) (Map.adjust f key m)

update :: Ord k => (a -> Maybe a) -> k -> NonEmptyMap k a -> Map.Map k a
update f key (NonEmptyMap (k, a) m) | key == k = case f a of
  Just a -> Map.insert k a m
  Nothing -> m
update f key (NonEmptyMap (k, a) m)           = Map.insert k a (Map.update f key m)

alter :: Ord k => (Maybe a -> Maybe a) -> k -> NonEmptyMap k a -> Map.Map k a
alter f key (NonEmptyMap (k, a) m) | key == k = case f (Just a) of
  Just a -> Map.insert k a m
  Nothing -> m
alter f key (NonEmptyMap (k, a) m)            = Map.insert k a (Map.alter f key m)

alterF :: forall f k a. (Functor f, Ord k) => (Maybe a -> f (Maybe a)) -> k -> NonEmptyMap k a -> f (Map.Map k a)
alterF f key (NonEmptyMap (k, a) m) | key == k = insideF <$> f (Just a)
  where
    insideF :: Maybe a -> Map.Map k a
    insideF (Just a)  = Map.insert k a m
    insideF Nothing   = m
alterF f key (NonEmptyMap (k, a) m)            = Map.insert k a <$> Map.alterF f key m

{--------------------------------------------------------------------
  Query
--------------------------------------------------------------------}

lookup :: Ord k => k -> NonEmptyMap k a -> Maybe a
lookup key (NonEmptyMap (k, a) m) | key == k = Just a
lookup key (NonEmptyMap _ m)                 = Map.lookup key m

(!?) :: Ord k => NonEmptyMap k a -> k -> Maybe a
(!?) nem k = lookup k nem

findWithDefault :: Ord k => a -> k -> NonEmptyMap k a -> a
findWithDefault a key nem = fromMaybe a (lookup key nem)

member :: Ord k => k -> NonEmptyMap k a -> Bool
member key nem = isJust (lookup key nem)

notMember :: Ord k => k -> NonEmptyMap k a -> Bool
notMember k nem = not $ member k nem

{--------------------------------------------------------------------
  Size
--------------------------------------------------------------------}
size :: NonEmptyMap k a -> Int
size (NonEmptyMap _ m) = 1 + Map.size m

{--------------------------------------------------------------------
  Conversions
--------------------------------------------------------------------}

-- Lists
toList :: NonEmptyMap k a -> [(k, a)]
toList (NonEmptyMap tup m) = tup : Map.toList m

toNonEmpty :: NonEmptyMap k a -> NonEmpty (k, a)
toNonEmpty (NonEmptyMap tup m) = tup :| Map.toList m

toMap :: Ord k => NonEmptyMap k a -> Map.Map k a
toMap (NonEmptyMap (k, a) m) = Map.insert k a m


{--------------------------------------------------------------------
  Map
--------------------------------------------------------------------}

mapWithKey :: (t -> b) -> NonEmptyMap k t -> NonEmptyMap k b
mapWithKey f (NonEmptyMap (k, v) map) =  NonEmptyMap (k, f v) (Map.map f map)

map :: (t -> b) -> NonEmptyMap k t -> NonEmptyMap k b
map = mapWithKey

mapKeysWith :: Ord k => (t1 -> t1 -> t1) -> (t2 -> k) -> NonEmptyMap t2 t1 -> NonEmptyMap k t1
mapKeysWith c f = fromNonEmptyWith c . NonEmptyList.map fFirst . Data.Map.NonEmpty.toNonEmpty
  where
    fFirst (x, y) = (f x, y)

mapKeys :: Ord k => (t2 -> k) -> NonEmptyMap t2 t1 -> NonEmptyMap k t1
mapKeys = mapKeysWith (\x _ -> x)


{--------------------------------------------------------------------
  Utils
--------------------------------------------------------------------}

foldlStrict :: (a -> b -> a) -> a -> [b] -> a
foldlStrict f z xs = case xs of
  [] -> z
  (x:xss) -> let z' = f z x in seq z' (foldlStrict f z' xss)
