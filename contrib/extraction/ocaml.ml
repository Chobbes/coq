(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*s Production of Ocaml syntax. *)

open Pp
open Util
open Names
open Nameops
open Term
open Miniml
open Table
open Mlutil
open Options
open Nametab

let current_module = ref None

(*s Some utility functions. *)

let rec collapse_type_app = function
  | (Tapp l1) :: l2 -> collapse_type_app (l1 @ l2)
  | l -> l

let open_par = function true -> str "(" | false -> (mt ())

let close_par = function true -> str ")" | false -> (mt ())

let pp_tvar id = 
  let s = string_of_id id in 
  if String.length s < 2 || s.[1]<>'\'' 
  then str ("'"^s)
  else str ("' "^s)

let pp_tuple f = function
  | [] -> (mt ())
  | [x] -> f x
  | l -> (str "(" ++
      	    prlist_with_sep (fun () -> (str "," ++ spc ())) f l ++
	    str ")")

let pp_boxed_tuple f = function
  | [] -> (mt ())
  | [x] -> f x
  | l -> (str "(" ++
      	    hov 0 (prlist_with_sep (fun () -> (str "," ++ spc ())) f l ++
		     str ")"))

let pp_abst = function
  | [] -> (mt ())
  | l  -> (str "fun " ++
             prlist_with_sep (fun () -> (str " ")) pr_id l ++
             str " ->" ++ spc ())

let pr_binding = function
  | [] -> (mt ())
  | l  -> (str " " ++ prlist_with_sep (fun () -> (str " ")) pr_id l)

let space_if = function true -> (str " ") | false -> (mt ())

let sec_space_if = function true -> (spc ()) | false -> (mt ())

(*s Generic renaming issues. *)

let rec rename_id id avoid = 
  if Idset.mem id avoid then rename_id (lift_ident id) avoid else id

let lowercase_id id = id_of_string (String.uncapitalize (string_of_id id))
let uppercase_id id = id_of_string (String.capitalize (string_of_id id))

(*s de Bruijn environments for programs *)

type env = identifier list * Idset.t

let rec rename_vars avoid = function
  | [] -> 
      [], avoid
  | id :: idl when id == prop_name ->
      (* we don't rename propositions binders *)
      let (idl', avoid') = rename_vars avoid idl in
      (id :: idl', avoid')
  | id :: idl ->
      let id' = rename_id (lowercase_id id) avoid in
      let (idl', avoid') = rename_vars (Idset.add id' avoid) idl in
      (id' :: idl', avoid')

let push_vars ids (db,avoid) =
  let ids',avoid' = rename_vars avoid ids in
  ids', (ids' @ db, avoid')

let get_db_name n (db,_) = List.nth db (pred n)

(*s Ocaml renaming issues. *)

let keywords =     
  List.fold_right (fun s -> Idset.add (id_of_string s))
  [ "and"; "as"; "assert"; "begin"; "class"; "constraint"; "do";
    "done"; "downto"; "else"; "end"; "exception"; "external"; "false";
    "for"; "fun"; "function"; "functor"; "if"; "in"; "include";
    "inherit"; "initializer"; "lazy"; "let"; "match"; "method";
    "module"; "mutable"; "new"; "object"; "of"; "open"; "or";
    "parser"; "private"; "rec"; "sig"; "struct"; "then"; "to"; "true";
    "try"; "type"; "val"; "virtual"; "when"; "while"; "with"; "mod";
    "land"; "lor"; "lxor"; "lsl"; "lsr"; "asr" ; "prop" ; "arity" ] 
  Idset.empty

let preamble _ =
  (str "type prop = unit" ++ fnl () ++
     str "let prop = ()" ++ fnl () ++ fnl () ++
     str "type arity = unit" ++ fnl () ++
     str "let arity = ()" ++ fnl () ++ fnl ())

(*s The pretty-printing functor. *)

module Make = functor(P : Mlpp_param) -> struct

let pp_type_global = P.pp_type_global 
let pp_global = P.pp_global
let rename_global = P.rename_global

let empty_env () = [], P.globals()

(*s Pretty-printing of types. [par] is a boolean indicating whether parentheses
    are needed or not. *)

let rec pp_type par t =
  let rec pp_rec par = function
    | Tvar id -> 
	pp_tvar id
    | Tapp l ->
	(match collapse_type_app l with
	   | [] -> assert false
	   | [t] -> pp_rec par t
	   | t::l -> (pp_tuple (pp_rec false) l ++ 
			sec_space_if (l <>[]) ++ 
			pp_rec false t))
    | Tarr (t1,t2) ->
	(open_par par ++ pp_rec true t1 ++ spc () ++ str "->" ++ spc () ++ 
	   pp_rec false t2 ++ close_par par)
    | Tglob r -> 
	pp_type_global r
    | Texn s -> 
	str ("unit (* " ^ s ^ " *)")
    | Tprop ->
	str "prop"
    | Tarity ->
	str "arity"
  in 
  hov 0 (pp_rec par t)

(*s Pretty-printing of expressions. [par] indicates whether
    parentheses are needed or not. [env] is the list of names for the
    de Bruijn variables. [args] is the list of collected arguments
    (already pretty-printed). *)

let expr_needs_par = function
  | MLlam _  -> true
  | MLcase _ -> true
  | _        -> false 

let rec pp_expr par env args = 
  let par' = args <> [] || par in 
  let apply st = match args with
    | [] -> st
    | _  -> hov 2 (open_par par ++ st ++ spc () ++
                     prlist_with_sep (fun () -> (spc ())) (fun s -> s) args ++
                     close_par par) 
  in
  function
    | MLrel n -> 
	let id = get_db_name n env in 
	apply (if string_of_id id = "_" then str "prop" else pr_id id)
	  (* HACK, should disappear soon *)
    | MLapp (f,args') ->
	let stl = List.map (pp_expr true env []) args' in
        pp_expr par env (stl @ args) f
    | MLlam _ as a -> 
      	let fl,a' = collect_lams a in
	let fl,env' = push_vars fl env in
	let st = (pp_abst (List.rev fl) ++ pp_expr false env' [] a') in
	(open_par par' ++ st ++ close_par par')
    | MLletin (id,a1,a2) ->
	let id',env' = push_vars [id] env in
	let par2 = not par' && expr_needs_par a2 in
	apply 
	  (hov 0 (open_par par' ++
		    hov 2 (str "let " ++ pr_id (List.hd id') ++ str " =" ++ spc () ++
			     pp_expr false env [] a1 ++ spc () ++ str "in") ++
		    spc () ++
		    pp_expr par2 env' [] a2 ++
		    close_par par'))
    | MLglob r -> 
	apply (pp_global r)
    | MLcons (r,[]) ->
	pp_global r
    | MLcons (r,[a]) ->
	(open_par par ++ pp_global r ++ spc () ++
	   pp_expr true env [] a ++ close_par par)
    | MLcons (r,args') ->
	(open_par par ++ pp_global r ++ spc () ++
	   pp_tuple (pp_expr true env []) args' ++ close_par par)
    | MLcase (t,[|x|])->
	apply 
	  (hov 0 (open_par par' ++ str "let " ++  
		    pp_one_pat 
		      (str " =" ++ spc () ++
			 pp_expr false env [] t ++ spc () ++ str "in") 
		      env x ++
		    close_par par'))
    | MLcase (t, pv) ->
      	apply
      	  (open_par par' ++
      	     v 0 (str "match " ++ pp_expr false env [] t ++ str " with" ++
		    fnl () ++ str "  " ++ pp_pat env pv) ++
	     close_par par')
    | MLfix (i,ids,defs) ->
	let ids',env' = push_vars (List.rev (Array.to_list ids)) env in
      	pp_fix par env' (Some i) (Array.of_list (List.rev ids'),defs) args
    | MLexn s -> 
	(open_par par ++ str "assert false" ++ spc () ++ 
	   str ("(* "^s^" *)") ++ close_par par)
    | MLprop ->
	str "prop"
    | MLarity ->
	str "arity"
    | MLcast (a,t) ->
	(open_par true ++ pp_expr false env args a ++ spc () ++ str ":" ++ spc () ++ 
	   pp_type false t ++ close_par true)
    | MLmagic a ->
	(open_par true ++ str "Obj.magic" ++ spc () ++ 
	   pp_expr false env args a ++ close_par true)

and pp_one_pat s env (r,ids,t) = 
  let ids,env' = push_vars (List.rev ids) env in
  let par = expr_needs_par t in
  let args = 
    if ids = [] then (mt ()) 
    else str " " ++ pp_boxed_tuple pr_id (List.rev ids) in 
  pp_global r ++ args ++ s ++ spc () ++ pp_expr par env' [] t
  
and pp_pat env pv = 
  prvect_with_sep (fun () -> (fnl () ++ str "| ")) 
    (fun x -> hov 2 (pp_one_pat (str " ->") env x)) pv

(*s names of the functions ([ids]) are already pushed in [env],
    and passed here just for convenience. *)

and pp_fix par env in_p (ids,bl) args =
  (open_par par ++ 
     v 0 (str "let rec " ++
	    prvect_with_sep
      	      (fun () -> (fnl () ++ str "and "))
	      (fun (fi,ti) -> pp_function env (pr_id fi) ti)
	      (array_map2 (fun id b -> (id,b)) ids bl) ++
	    fnl () ++
	    match in_p with
	      | Some j -> 
      		  hov 2 (str "in " ++ pr_id (ids.(j)) ++
			   if args <> [] then
			     (str " " ++ 
				prlist_with_sep (fun () -> (str " "))
				  (fun s -> s) args)
			   else
			     (mt ()))
	      | None -> 
		  (mt ())) ++
     close_par par)

and pp_function env f t =
  let bl,t' = collect_lams t in
  let bl,env' = push_vars bl env in
  let is_function pv =
    let ktl = array_map_to_list (fun (_,l,t0) -> (List.length l,t0)) pv in
    not (List.exists (fun (k,t0) -> Mlutil.occurs (k+1) t0) ktl)
  in
  match t' with 
    | MLcase(MLrel 1,pv) ->
	if is_function pv then
	  (f ++ pr_binding (List.rev (List.tl bl)) ++
       	     str " = function" ++ fnl () ++
	     v 0 (str "  " ++ pp_pat env' pv))
	else
          (f ++ pr_binding (List.rev bl) ++ 
             str " = match " ++
	     pr_id (List.hd bl) ++ str " with" ++ fnl () ++
	     v 0 (str "  " ++ pp_pat env' pv))
	  
    | _ -> (f ++ pr_binding (List.rev bl) ++
	      str " =" ++ fnl () ++ str "  " ++
	      hov 2 (pp_expr false env' [] t'))
	
let pp_ast a = hov 0 (pp_expr false (empty_env ()) [] a)

(*s Pretty-printing of inductive types declaration. *)

let pp_parameters l = 
  (pp_tuple pp_tvar l ++ space_if (l<>[]))

let pp_one_inductive (pl,name,cl) =
  let pp_constructor (id,l) =
    (pp_global id ++
       match l with
         | [] -> (mt ()) 
	 | _  -> (str " of " ++
      	       	    prlist_with_sep 
		      (fun () -> (spc () ++ str "* ")) (pp_type true) l))
  in
  (pp_parameters pl ++ pp_type_global name ++ str " =" ++ 
     (fnl () ++
	v 0 (str "    " ++
	       prlist_with_sep (fun () -> (fnl () ++ str "  | "))
                 (fun c -> hov 2 (pp_constructor c)) cl)))
  
let pp_inductive il =
  (str "type " ++
     prlist_with_sep (fun () -> (fnl () ++ str "and ")) pp_one_inductive il ++
     fnl ())

(*s Pretty-printing of a declaration. *)

let warning_coinductive r = 
  warn (hov 0 
	  (str "You are trying to extract the CoInductive definition" ++ spc () ++
	     Printer.pr_global r ++ spc () ++ str "in Ocaml." ++ spc () ++ 
	     str "This is in general NOT a good idea," ++ spc () ++ 
	     str "since Ocaml is not lazy." ++ spc () ++
	     str "You should consider using Haskell instead."))

let pp_decl = function
  | Dtype ([], _) -> 
      if P.toplevel then hov 0 (str " prop (* Logic inductive *)" ++ fnl ())
      else (mt ()) 
  | Dtype ((_,r,_)::_ as i, cofix) -> 
      if cofix && (not P.toplevel) then if_verbose warning_coinductive r; 
      hov 0 (pp_inductive i)
  | Dabbrev (r, l, t) ->
      hov 0 (str "type" ++ spc () ++ pp_parameters l ++ 
	       pp_type_global r ++ spc () ++ str "=" ++ spc () ++ 
	       pp_type false  t ++ fnl ())
  | Dglob (r, MLfix (_,[|_|],[|def|])) ->
      let id = rename_global r in
      let env' = [id], P.globals() in
      (hov 2 (pp_fix false env' None ([|id|],[|def|]) []))
  | Dglob (r, a) ->
      hov 0 (str "let " ++ 
	       pp_function (empty_env ()) (pp_global r) a ++ fnl ())
  | Dcustom (r,s) -> 
      hov 0 (str "let " ++ pp_global r ++ 
	       str " =" ++ spc () ++ str s ++ fnl ())

let pp_type = pp_type false

end

