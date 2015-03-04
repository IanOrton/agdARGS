module agdARGS.Data.Arguments where

open import Level
open import Data.Unit
open import Data.Bool
open import Data.Product
open import Data.Sum as Sum
open import Data.Maybe as Maybe
open import Data.String as Str hiding (strictTotalOrder)

open import Function
open import Relation.Binary
import Relation.Binary.On as On

open import Algebra

record RawMagma (ℓ : Level) : Set (suc ℓ) where
  field
    Carrier : Set ℓ
    _∙_     : Carrier → Carrier → Carrier

data Domain (ℓ : Level) : Set (suc ℓ) where
  None :                    Domain ℓ
  Some : (S : Set ℓ)      → Domain ℓ
  ALot : (M : RawMagma ℓ) → Domain ℓ

elimDomain :
  {ℓ ℓᵖ : Level} {P : Domain ℓ → Set ℓᵖ}
  (dNone : P None) (dSome : ∀ S → P (Some S)) (dALot : ∀ M → P (ALot M)) →
  (d : Domain ℓ) → P d
elimDomain dNone dSome dALot None     = dNone
elimDomain dNone dSome dALot (Some S) = dSome S
elimDomain dNone dSome dALot (ALot M) = dALot M

Parser : {ℓ : Level} → Domain ℓ → Set ℓ
Parser =
  let parseOne S = String → String ⊎ S
  in elimDomain (Lift ⊤) parseOne (parseOne ∘ RawMagma.Carrier)

record Argument (ℓ : Level) : Set (suc ℓ) where
  field
    name        : String
    description : String
    flag        : String
    optional    : Bool
    domain      : Domain ℓ
    parser      : Parser domain

open Argument

strictTotalOrder : (ℓ : Level) → StrictTotalOrder _ _ _
strictTotalOrder ℓ = On.strictTotalOrder Str.strictTotalOrder (flag {ℓ})

module Arguments (ℓ : Level) where

  open import agdARGS.Data.Infinities
  open import agdARGS.Data.UniqueSortedList (strictTotalOrder ℓ) public

  Arguments : Set (suc ℓ)
  Arguments = UniqueSortedList -∞ +∞

  Options : (m : Argument ℓ → Set ℓ) {lb ub : _} (args : UniqueSortedList lb ub) → Set ℓ
  Options m (lt ■)           = Lift ⊤
  Options m (hd , lt ∷ args) = m hd × Options m args

  getOptions :
    (m : Argument ℓ → Set ℓ) {lb ub : _} {args : UniqueSortedList lb ub} {arg : Argument ℓ}
    (pr : arg ∈ args) → Options m args → m arg
  getOptions m z      = proj₁
  getOptions m (s pr) = getOptions m pr ∘ proj₂

  SetDomain : Domain ℓ → Set ℓ
  SetDomain = elimDomain {P = const $ Set ℓ} (Lift ⊤) id (RawMagma.Carrier)

  MaybeMode : Argument ℓ → Set ℓ
  MaybeMode = Maybe ∘ SetDomain ∘ domain

  defaultOptions : {lb ub : _} (args : UniqueSortedList lb ub) → Options MaybeMode args
  defaultOptions (lt ■)           = lift tt
  defaultOptions (hd , lt ∷ args) = nothing , defaultOptions args

  open import Relation.Nullary
  open import Relation.Binary.PropositionalEquality

  findArgument : (str : String) (args : Arguments) →
                 Dec (Σ[ arg ∈ Argument ℓ ] (arg ∈ args × flag arg ≡ str))
  findArgument str = search Str._≟_ flag str


  open import Category.Monad

  mapMOptions :
     {M : Set ℓ → Set ℓ} (MM : RawMonad M) →
     {lb ub : _} (args : UniqueSortedList lb ub) {f g : Argument ℓ → Set ℓ}
     (upd : {arg : Argument ℓ} (pr : arg ∈ args) → f arg → M (g arg)) →
     Options f args → M (Options g args)
  mapMOptions MM (lt ■)         upd opts       = let open RawMonad MM in return opts
  mapMOptions MM (hd , lt ∷ xs) upd (v , opts) =
    upd z v                          >>= λ w  →
    mapMOptions MM xs (upd ∘ s) opts >>= λ ws →
    return (w , ws)
    where open RawMonad MM

  updateMOptions :
     {M : Set ℓ → Set ℓ} (MM : RawMonad M) →
     {lb ub : _} {args : UniqueSortedList lb ub} {f : Argument ℓ → Set ℓ}
     {arg : Argument ℓ} (pr : arg ∈ args) (updArg : f arg → M (f arg)) →
     Options f args → M (Options f args)
  updateMOptions {M} MM {args = args} {f} {arg} pr updArgs = mapMOptions MM _ (upd pr updArgs)
    where
      open RawMonad MM

      upd : {lb ub : _} {args : UniqueSortedList lb ub} {arg : Argument ℓ} →
            arg ∈ args → (upd : f arg → M (f arg)) → 
            {arg : Argument ℓ} → arg ∈ args → f arg → M (f arg)
      upd z       f z       = f
      upd z       f (s pr₂) = return
      upd (s pr₁) f z       = return
      upd (s pr₁) f (s pr₂) = upd pr₁ f pr₂

  monadSum : {ℓᵃ : Level} (A : Set ℓᵃ) {ℓᵇ : Level} → RawMonad ((Set (ℓᵃ ⊔ ℓᵇ) → Set (ℓᵃ ⊔ ℓᵇ)) ∋ _⊎_ A )
  monadSum A {ℓᵇ} = record { return = inj₂ ; _>>=_ = [ flip (const inj₁) , flip _$_ ]′ }

  set : {args : Arguments} {arg : Argument ℓ} (pr : arg ∈ args) (v : SetDomain (domain arg)) →
        Options MaybeMode args → String ⊎ Options MaybeMode args
  set {_} {arg} pr v = updateMOptions (monadSum String) pr $ elimDomain {P = P} PNone PSome PALot (domain arg) v
    where
      P : Domain ℓ → Set ℓ
      P d = SetDomain d → Maybe (SetDomain d) → String ⊎ Maybe (SetDomain d)

      PNone : P None
      PNone new = maybe′ (const (inj₁ ("Flag " ++ flag arg ++ " set more than once"))) (inj₂ (just new))

      PSome : (S : Set ℓ) → P (Some S)
      PSome S new = maybe′ (const (inj₁ ("Option " ++ flag arg ++ " used more than once"))) (inj₂ (just new))

      PALot : (M : RawMagma ℓ) → P (ALot M)
      PALot M new = maybe′ (λ old → inj₂ (just (new ∙ old))) (inj₂ (just new))
        where open RawMagma M

  open import Data.Nat as Nat
  open import Data.List using ([] ; _∷_ ; List)
  open import lib.Nullary

  ParseResult : Arguments → Maybe (Argument ℓ) → Set ℓ
  ParseResult args default = maybe′ MaybeMode (Lift ⊤) default × Options MaybeMode args

  parse : List String → (default : Maybe (Argument ℓ)) (args : Arguments) → String ⊎ ParseResult args default
  parse xs default args = go xs (initDefault , defaultOptions args)
    where
      initDefault : maybe′ MaybeMode (Lift ⊤) default
      initDefault = maybe {B = maybe′ MaybeMode (Lift ⊤)} (λ _ → nothing) (lift tt) default

      failure : String → ParseResult args default → String ⊎ ParseResult args default
      failure x (opt , opts) =
        (case default
         return (λ d → maybe MaybeMode (Lift ⊤) d → String ⊎ ParseResult args d)
         of λ { nothing    _ → inj₁ ("Invalid option: " ++ x)
              ; (just arg) →
                (case (domain arg)
                return (λ d → Parser d → Maybe (SetDomain d) →
                              String ⊎ (Maybe (SetDomain d) × Options MaybeMode args))
                of λ { None     p old → inj₁ "Defaulting should always work on a RawMagma"
                     ; (Some S) p old → inj₁ "Defaulting should always work on a RawMagma"
                     ; (ALot M) p old →
                         let open RawMonad (monadSum String {ℓ})
                             open RawMagma M
                         in (λ v → (maybe (λ w → just (v ∙ w)) (just v) old , opts)) <$> p x
                     }) (parser arg)
              }) opt

      go : List String → ParseResult args default → String ⊎ ParseResult args default
      go []           opts         = inj₂ opts
      go (x ∷ [])     (opt , opts) =
        flip (dec (findArgument x args))
        -- flag not found
        (const $ failure x (opt , opts))
        -- flag found
        $ λ elpreq →
        let sd = case domain (proj₁ elpreq)
                 return (λ d → String ⊎ SetDomain d)
                 of λ { None → inj₂ (lift tt)
                      ; _    → inj₁ ("Option " ++ flag (proj₁ elpreq) ++ " expects an argument; none given") }
            open RawMonad (monadSum String {ℓ})
        in sd >>= λ v → set (proj₁ (proj₂ elpreq)) v opts >>= λ opts′ → return (opt , opts′)
      go (x ∷ y ∷ xs) (opt , opts) =
        flip (dec (findArgument x args))
        -- flag not found
        (const $
          let open RawMonad (monadSum String {ℓ})
          in failure x (opt , opts) >>= go (y ∷ xs))
        -- flag found
        $ λ elpreq →
        let vb = (case domain (proj₁ elpreq)
                  return (λ d → Parser d → String ⊎ (SetDomain d × Bool))
                  of let open RawMonad (monadSum String {ℓ}) in λ
                     { None     p → inj₂ (lift tt , false)
                     ; (Some S) p → (λ s → s , true) <$> p y
                     ; (ALot M) p → (λ s → s , true) <$> p y }
                 ) (parser (proj₁ elpreq))
            open RawMonad (monadSum String {ℓ})
        in vb >>= uncurry λ v b → set (proj₁ (proj₂ elpreq)) v opts >>= λ opts′ →
           (if b then go xs else go (y ∷ xs)) (opt , opts′)

{-
  validate : {args : Arguments} → Options (const Maybe) args →
             let f a = if optional a then Maybe else id
             in Maybe $ Options f args
  validate = {!!}


  parse : List String → (args : Arguments) → Maybe $ Options _ args
  parse xs args = preParse xs args >>= validate
    where open RawMonad Maybe.monad
-}