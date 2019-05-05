open Extractable
open Plugin_core
open BasicAst

open Quoter
open Ast_quoter


let of_constr (env : Environ.env) (t : Constr.t) : Ast0.term =
  Ast_quoter.quote_term env t

open Ast_denoter
  (* todo(gmm): determine what of these already exist. *)
let rec to_constr_ev (evm : Evd.evar_map) (t : Ast0.term) : Evd.evar_map * Constr.t =
  ExtractionDenote.denote_term evm t

let to_constr (t : Ast0.term) : Constr.t =
  snd (to_constr_ev Evd.empty t)


let to_string : char list -> string =
  Quoted.list_to_string

let of_string : string -> char list =
  Quoted.string_to_list

let to_reduction_strategy (s : Common0.reductionStrategy) : Plugin_core.reduction_strategy =
  match s with
   | Common0.Coq_cbv -> Plugin_core.rs_cbv
   | Common0.Coq_cbn -> Plugin_core.rs_cbn
   | Common0.Coq_hnf -> Plugin_core.rs_hnf
   | Common0.Coq_all -> Plugin_core.rs_all
   | Common0.Coq_lazy -> Plugin_core.rs_lazy
   | Common0.Coq_unfold x -> failwith "not yet implemented: to_reduction_strategy"

let to_ident : char list ->  Names.Id.t =
  Ast_quoter.unquote_ident

let of_ident (id : Names.Id.t) : char list =
  of_string (Names.Id.to_string id)

let of_global_reference : Plugin_core.global_reference -> BasicAst.global_reference =
  Ast_quoter.quote_global_reference

let to_qualid (c : char list) : Libnames.qualid =
  Libnames.qualid_of_string (to_string c)

let of_qualid (q : Libnames.qualid) : char list =
  of_string (Libnames.string_of_qualid q)

let of_kername : Names.KerName.t -> char list =
  Ast_quoter.quote_kn

(* TODO: check that [s] was fully qualified *)
let to_kername (s : char list) : Names.KerName.t =
  match Nametab.locate (Ast_quoter.unquote_kn s) with
   | Globnames.VarRef vr -> failwith "not yet implemented"
   | Globnames.ConstRef c -> Names.Constant.canonical c
   | Globnames.IndRef i -> Names.MutInd.canonical (fst i)
   | Globnames.ConstructRef c -> failwith "not yet implemented"

(* todo(gmm): this definition adapted from quoter.ml *)
let quote_rel_decl env = function
  | Context.Rel.Declaration.LocalAssum (na, t) ->
    let t' = Ast_quoter.quote_term env t in
    Ast_quoter.quote_context_decl (Ast_quoter.quote_name na) None t'
  | Context.Rel.Declaration.LocalDef (na, b, t) ->
    let b' = Ast_quoter.quote_term env b in
    let t' = Ast_quoter.quote_term env t in
    Ast_quoter.quote_context_decl (Ast_quoter.quote_name na) (Some b') t'

(* todo(gmm): this definition adapted from quoter.ml *)
let quote_rel_context env ctx =
  let decls, env =
    List.fold_right (fun decl (ds, env) ->
        let x = quote_rel_decl env decl in
        (x :: ds, Environ.push_rel decl env))
      ctx ([],env) in
  Ast_quoter.quote_context decls

(* todo(gmm): this definition adapted from quoter.ml (the body of quote_minductive_type) *)
let of_mib (env : Environ.env) (t : Names.MutInd.t) (mib : Plugin_core.mutual_inductive_body) : Ast0.mutual_inductive_body =
  let open Declarations in
  let uctx = get_abstract_inductive_universes mib.mind_universes in
  let inst = Univ.UContext.instance uctx in
  let indtys =
    (CArray.map_to_list (fun oib ->
         let ty = Inductive.type_of_inductive env ((mib,oib),inst) in
         (Context.Rel.Declaration.LocalAssum (Names.Name oib.mind_typename, ty))) mib.mind_packets)
  in
  let envind = Environ.push_rel_context (List.rev indtys) env in
  let (ls,acc) =
    List.fold_left (fun (ls,acc) oib ->
	let named_ctors =
	  CList.combine3
	    (Array.to_list oib.mind_consnames)
	    (Array.to_list oib.mind_user_lc)
	    (Array.to_list oib.mind_consnrealargs)
	in
        let indty = Inductive.type_of_inductive env ((mib,oib),inst) in
        let indty = Ast_quoter.quote_term env indty in
	let (reified_ctors,acc) =
	  List.fold_left (fun (ls,acc) (nm,ty,ar) ->
	      Tm_util.debug (fun () -> Pp.(str "opt_hnf_ctor_types:" ++ spc () ++
                                   bool !opt_hnf_ctor_types)) ;
	      let ty = if !opt_hnf_ctor_types then hnf_type envind ty else ty in
	      let ty = quote_term acc ty in
	      ((Ast_quoter.quote_ident nm, ty, Ast_quoter.quote_int ar) :: ls, acc))
	    ([],acc) named_ctors
	in
        let projs, acc =
          match mib.mind_record with
          | Some (Some (id, csts, ps)) ->
            let ctxwolet = Termops.smash_rel_context mib.mind_params_ctxt in
            let indty = Constr.mkApp (Constr.mkIndU ((t,0),inst),
                                      Context.Rel.to_extended_vect Constr.mkRel 0 ctxwolet) in
            let indbinder = Context.Rel.Declaration.LocalAssum (Names.Name id,indty) in
            let envpars = Environ.push_rel_context (indbinder :: ctxwolet) env in
            let ps, acc = CArray.fold_right2 (fun cst pb (ls,acc) ->
                let ty = quote_term envpars pb.proj_type in
                let kn = Names.KerName.label (Names.Constant.canonical cst) in
                let na = Ast_quoter.quote_ident (Names.Label.to_id kn) in
                ((na, ty) :: ls, acc)) csts ps ([],acc)
            in ps, acc
          | _ -> [], acc
        in
        let sf = List.map Ast_quoter.quote_sort_family oib.mind_kelim in
	(Ast_quoter.quote_ident oib.mind_typename, indty, sf, (List.rev reified_ctors), projs) :: ls, acc)
      ([],env) (Array.to_list mib.mind_packets)
  in
  let nparams = Ast_quoter.quote_int mib.mind_nparams in
  let paramsctx = quote_rel_context env mib.mind_params_ctxt in
  let uctx = quote_abstract_inductive_universes mib.mind_universes in
  let bodies = List.map Ast_quoter.mk_one_inductive_body (List.rev ls) in
  Ast_quoter.mk_mutual_inductive_body nparams paramsctx bodies uctx

let to_mutual_inductive_entry evm (x : Ast0.mutual_inductive_entry) : Plugin_core.mutual_inductive_entry =
  let unquote_ident = Ast_denoter.ExtractionDenoter.unquote_ident in
  let open Entries in
  { mind_entry_record =
      begin
        match x.Ast0.mind_entry_record with
        | None -> None
        | Some None -> Some None
        | Some (Some i) -> Some (Some (unquote_ident i))
      end
  ; mind_entry_finite = x.Ast0.mind_entry_finite
  ; mind_entry_params =
      begin
        let f (id, le) =
          (unquote_ident id,
           match le with
           | Ast0.LocalDef x -> Entries.LocalDefEntry (to_constr x)
           | Ast0.LocalAssum x -> Entries.LocalAssumEntry (to_constr x)) in
        List.map f x.Ast0.mind_entry_params
      end
  ; mind_entry_inds =
      begin
        let unquote_one_inductive_entry x =
          { mind_entry_typename = unquote_ident x.Ast0.mind_entry_typename
          ; mind_entry_arity = to_constr x.Ast0.mind_entry_arity
          ; mind_entry_template = x.Ast0.mind_entry_template
          ; mind_entry_consnames = List.map unquote_ident x.Ast0.mind_entry_consnames
          ; mind_entry_lc = List.map to_constr x.Ast0.mind_entry_lc
          } in
        List.map unquote_one_inductive_entry x.Ast0.mind_entry_inds
      end
  ; mind_entry_universes =
      begin
        let unquote_level l = Ast_quoter.unquote_level l in
        let unquote_univ_constraint (z : Univ0.ConstraintSet.Raw.elt) =
          let ((l1, c), l2) = z in
          (unquote_level l1, c, unquote_level l2)
        in
        let unquote_constraints (c : Univ0.constraints) : Univ.Constraint.t =
          let f set c =
            let c = unquote_univ_constraint c in Univ.Constraint.add c set
          in
          List.fold_left f Univ.Constraint.empty c
        in
        let unquote_universe_instance (ls : Univ0.Instance.t) : Univ.Instance.t =
          let l = List.map unquote_level ls in
          Univ.Instance.of_array (Array.of_list l)
        in
        let denote_ucontext ((ls,cs) : Univ0.Instance.t * Univ0.constraints) : Univ.UContext.t =
          Univ.UContext.make (unquote_universe_instance ls, unquote_constraints cs) in
        let denote_cumulativity (ci : Univ0.CumulativityInfo.t) : Univ.CumulativityInfo.t =
          let ctx,var = ci in
          Univ.CumulativityInfo.make (denote_ucontext ctx, Array.of_list var)
        in
        let denote_context_set (ctx : Univ0.UContext.t) : Univ.ContextSet.t =
          Univ.ContextSet.of_context (denote_ucontext ctx)
        in
        match x.Ast0.mind_entry_universes with
        | Univ0.Monomorphic_ctx ctx ->
           Entries.Monomorphic_ind_entry (denote_context_set ctx)
        | Univ0.Polymorphic_ctx ctx ->
           Entries.Polymorphic_ind_entry (denote_ucontext ctx)
        | Univ0.Cumulative_ctx ctx ->
           Entries.Cumulative_ind_entry (denote_cumulativity ctx)
      end
  ; mind_entry_private = x.Ast0.mind_entry_private
  }

(* note(gmm): code taken from quoter.ml (quote_entry_aux) *)
let of_constant_entry (env : Environ.env) (cd : Plugin_core.constant_entry) : Ast0.constant_entry =
  let open Declarations in
  let ty = quote_term env cd.const_type in
  let body = match cd.const_body with
    | Undef _ -> None
    | Def cs -> Some (Ast_quoter.quote_term env (Mod_subst.force_constr cs))
    | OpaqueDef cs ->
      if true
      then Some (Ast_quoter.quote_term env (Opaqueproof.force_proof (Global.opaque_tables ()) cs))
      else None
  in
  let uctx = quote_constant_uctx cd.const_universes in
  Ast_quoter.quote_constant_entry (ty, body, uctx)

(* what about the overflow?
  efficiency? extract to bigint using Coq directives and convert to int here? *)
let of_nat (t : Datatypes.nat) : int =
  failwith "of_constr"

let of_cast_kind (ck: quoted_cast_kind) : Constr.cast_kind = ck


let tmOfConstr (t : Constr.t) : Ast0.term tm =
  Plugin_core.with_env_evm (fun env _ -> tmReturn (of_constr env t))

let tmOfMib (ti : Names.MutInd.t) (t : Plugin_core.mutual_inductive_body) : Ast0.mutual_inductive_body tm =
  Plugin_core.with_env_evm (fun env _ -> tmReturn (of_mib env ti t))

let tmOfConstantEntry (t : Plugin_core.constant_entry) : Ast0.constant_entry tm =
  Plugin_core.with_env_evm (fun env _ -> tmReturn (of_constant_entry env t))

let tmToMie x =
  Plugin_core.with_env_evm (fun env _ -> tmReturn (to_mutual_inductive_entry env x))

(*
let dbg = function
    Coq_tmReturn _ -> "tmReturn"
  | Coq_tmBind _ -> "tmBind"
  | Coq_tmPrint _ -> "tmPrint"
  | Coq_tmMsg msg -> "tmMsg"
  | Coq_tmFail err -> "tmFail"
  | Coq_tmEval (r,t) -> "tmEval"
  | Coq_tmDefinition (nm, typ, trm) -> "tmDefinition"
  | Coq_tmAxiom (nm, typ) -> "tmAxiom"
  | Coq_tmLemma (nm, typ) -> "tmLemma"
  | Coq_tmFreshName nm -> "tmFreshName"
  | Coq_tmAbout id -> "tmAbout"
  | Coq_tmCurrentModPath -> "tmCurrentModPath"
  | Coq_tmQuoteInductive kn -> "tmQuoteInductive"
  | Coq_tmQuoteUniverses -> "tmQuoteUniverses"
  | Coq_tmQuoteConstant (kn, b) -> "tmQuoteConstant"
  | Coq_tmInductive i -> "tmInductive"
  | Coq_tmExistingInstance k -> "tmExistingInstance"
  | Coq_tmInferInstance t -> "tmInferInstance"
*)

let rec interp_tm (t : 'a coq_TM) : 'a tm =
(*  Feedback.msg_debug Pp.(str (dbg t)) ; *)
  match t with
  | Coq_tmReturn x -> tmReturn x
  | Coq_tmBind (c, k) -> tmBind (interp_tm c) (fun x -> interp_tm (k x))
  | Coq_tmPrint t -> Obj.magic (tmPrint (to_constr t))
  | Coq_tmMsg msg -> Obj.magic (tmMsg (to_string msg))
  | Coq_tmFail err -> tmFailString (to_string err)
  | Coq_tmEval (r,t) ->
    tmBind (tmEval (to_reduction_strategy r) (to_constr t))
           (fun x -> Obj.magic (tmOfConstr x))
  | Coq_tmDefinition (nm, typ, trm) ->
    let typ =
      match typ with
        None -> None
      | Some typ -> Some (to_constr typ)
    in
    tmMap (fun x -> Obj.magic (of_kername x))
          (tmDefinition (to_ident nm) typ (to_constr trm))
  | Coq_tmAxiom (nm, typ) ->
    tmMap (fun x -> Obj.magic (of_kername x))
          (tmAxiom (to_ident nm) (to_constr typ))
  | Coq_tmLemma (nm, typ) ->
    tmMap (fun x -> Obj.magic (of_kername x))
          (tmLemma (to_ident nm) (to_constr typ))
  | Coq_tmFreshName nm ->
    tmMap (fun x -> Obj.magic (of_ident x))
          (tmFreshName (to_ident nm))
  | Coq_tmAbout id ->
    tmMap (function
             None -> Obj.magic None
           | Some gr -> Obj.magic (Some (of_global_reference gr)))
          (tmAbout (to_qualid id))
  | Coq_tmCurrentModPath ->
    tmMap (fun mp -> Obj.magic (of_string (Names.ModPath.to_string mp)))
          tmCurrentModPath
  | Coq_tmQuoteInductive kn ->
    tmBind (tmQuoteInductive (to_kername kn))
           (function
             None -> Obj.magic (tmFail Pp.(str "inductive does not exist"))
           | Some (mi, mib) -> Obj.magic (tmOfMib mi mib))
  | Coq_tmQuoteUniverses ->
    tmMap (fun x -> failwith "tmQuoteUniverses") tmQuoteUniverses
  | Coq_tmQuoteConstant (kn, b) ->
    tmBind (tmQuoteConstant (to_kername kn) b)
           (fun x -> Obj.magic (tmOfConstantEntry x))
  | Coq_tmInductive i ->
     tmBind (tmToMie i)
       (fun x -> tmMap (fun _ -> Obj.magic ()) (tmInductive x))
  | Coq_tmExistingInstance k ->
    Obj.magic (tmExistingInstance (to_kername k))
  | Coq_tmInferInstance t ->
    tmBind (tmInferInstance (to_constr t))
      (function
          None -> Obj.magic None
        | Some inst -> Obj.magic (tmMap (fun x -> Some x) (tmOfConstr inst)))

let run_vernac (c : 'a coq_TM) : unit =
  Plugin_core.run_vernac (interp_tm (Obj.magic c))