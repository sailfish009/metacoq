(* Distributed under the terms of the MIT license.   *)
From Equations Require Import Equations.
From Coq Require Import Bool String List Program BinPos Compare_dec.
From MetaCoq.Template Require Import config utils.
From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICInduction
     PCUICLiftSubst PCUICUnivSubst PCUICTyping PCUICWeakeningEnv PCUICWeakening
     PCUICSubstitution PCUICClosed.
Require Import ssreflect ssrbool.
Require Import String.
From MetaCoq Require Import LibHypsNaming.
Local Open Scope string_scope.
Set Asymmetric Patterns.
Require Import Equations.Prop.DepElim.

Section Generation.
  Context `{cf : config.checker_flags}.

  Definition isWfArity_or_Type Σ Γ T : Type := (isWfArity typing Σ Γ T + isType Σ Γ T).

  Inductive typing_spine (Σ : global_env_ext) (Γ : context) :
    term -> list term -> term -> Type :=
  | type_spine_nil ty ty' :
      isWfArity_or_Type Σ Γ ty' ->
      Σ ;;; Γ |- ty <= ty' ->
      typing_spine Σ Γ ty [] ty'

  | type_spine_cons hd tl na A B T B' :
      isWfArity_or_Type Σ Γ (tProd na A B) ->
      Σ ;;; Γ |- T <= tProd na A B ->
      Σ ;;; Γ |- hd : A ->
      typing_spine Σ Γ (subst10 hd B) tl B' ->
      typing_spine Σ Γ T (hd :: tl) B'.

  Lemma type_mkApps Σ Γ t u T t_ty :
    Σ ;;; Γ |- t : t_ty ->
    typing_spine Σ Γ t_ty u T ->
    Σ ;;; Γ |- mkApps t u : T.
  Proof.
    intros Ht Hsp.
    revert t Ht. induction Hsp; simpl; auto.
    intros t Ht. eapply type_Cumul; eauto.

    intros.
    specialize (IHHsp (tApp t0 hd)). apply IHHsp.
    eapply type_App.
    eapply type_Cumul; eauto. eauto.
  Qed.

  Derive NoConfusion NoConfusionHom for term.
  Derive NoConfusion NoConfusionHom for context_decl.
  Derive NoConfusion NoConfusionHom for list.
  Derive NoConfusion NoConfusionHom for option.

  Lemma type_it_mkLambda_or_LetIn :
    forall Σ Γ Δ t A,
      Σ ;;; Γ ,,, Δ |- t : A ->
      Σ ;;; Γ |- it_mkLambda_or_LetIn Δ t : it_mkProd_or_LetIn Δ A.
  Proof.
    intros Σ Γ Δ t A h.
    induction Δ as [| [na [b|] B] Δ ih ] in t, A, h |- *.
    - assumption.
    - simpl. cbn. eapply ih.
      simpl in h. pose proof (typing_wf_local h) as hc.
      dependent induction hc. all: inversion H. subst.
      cbn in t1, t0. destruct t0.
      econstructor ; eassumption.
    - simpl. cbn. eapply ih.
      pose proof (typing_wf_local h) as hc. cbn in hc.
      dependent induction hc. all: inversion H. subst.
      cbn in t0. destruct t0.
      econstructor ; eassumption.
  Qed.

End Generation.