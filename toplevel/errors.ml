
(* $Id$ *)

open Pp
open Util
open Ast
open Indtypes
open Type_errors
open Lexer

let print_loc loc =
  if loc = dummy_loc then 
    [< 'sTR"<unknown>" >]
  else 
    [< 'iNT (fst loc); 'sTR"-"; 'iNT (snd loc) >]

let guill s = "\""^s^"\""

let where s =
  if !Options.debug then  [< 'sTR"in "; 'sTR s; 'sTR":"; 'sPC >] else [<>]

let report () = [< 'sTR "."; 'sPC; 'sTR "Please report." >]

(* assumption : explain_sys_exn does NOT end with a 'FNL anymore! *)

let rec explain_exn_default = function
  | Stream.Failure -> 
      hOV 0 [< 'sTR "Anomaly: Uncaught Stream.Failure." >]
  | Stream.Error txt -> 
      hOV 0 [< 'sTR "Syntax error: "; 'sTR txt >]
  | Token.Error txt -> 
      hOV 0 [< 'sTR "Syntax error: "; 'sTR txt >]
  | Sys_error msg -> 
      hOV 0 [< 'sTR "Error: OS: "; 'sTR msg >]
  | UserError(s,pps) -> 
      hOV 1 [< 'sTR"Error: "; where s; pps >]
  | Out_of_memory -> 
      hOV 0 [< 'sTR "Out of memory" >]
  | Stack_overflow -> 
      hOV 0 [< 'sTR "Stack overflow" >]
  | Ast.No_match s -> 
      hOV 0 [< 'sTR "Anomaly: Ast matching error: "; 'sTR s >]
  | Anomaly (s,pps) -> 
      hOV 1 [< 'sTR "Anomaly: "; where s; pps; report () >]
  | Match_failure(filename,pos1,pos2) ->
      hOV 1 [< 'sTR "Anomaly: Match failure in file ";
	       'sTR (guill filename); 'sTR " from char #";
	       'iNT pos1; 'sTR " to #"; 'iNT pos2;
	       report () >]
  | Not_found -> 
      hOV 0 [< 'sTR "Anomaly: Search error"; report () >]
  | Failure s -> 
      hOV 0 [< 'sTR "Anomaly: Failure "; 'sTR (guill s); report () >]
  | Invalid_argument s -> 
      hOV 0 [< 'sTR "Anomaly: Invalid argument "; 'sTR (guill s); report () >]
  | Sys.Break -> 
      hOV 0 [< 'fNL; 'sTR"User Interrupt." >]
  | Univ.UniverseInconsistency -> 
      hOV 0 [< 'sTR "Error: Universe Inconsistency." >]
  | TypeError(k,ctx,te) -> 
      hOV 0 [< 'sTR "Error:"; 'sPC; Himsg.explain_type_error k ctx te >]
  | InductiveError e -> 
      hOV 0 [< 'sTR "Error:"; 'sPC; Himsg.explain_inductive_error e >]
  | Logic.RefinerError e -> 
      hOV 0 [< 'sTR "Error:"; 'sPC; Himsg.explain_refiner_error e >]
  | Tacmach.FailError i ->
      hOV 0 [< 'sTR "Error: Fail tactic always fails (level "; 
	       'iNT i; 'sTR")." >]
  | Stdpp.Exc_located (loc,exc) ->
      hOV 0 [< if loc = Ast.dummy_loc then [<>]
               else [< 'sTR"At location "; print_loc loc; 'sTR":"; 'fNL >];
               explain_exn_default exc >]
  | Lexer.Error Illegal_character -> 
      hOV 0 [< 'sTR "Syntax error: Illegal character." >]
  | Lexer.Error Unterminated_comment -> 
      hOV 0 [< 'sTR "Syntax error: Unterminated comment." >]
  | Lexer.Error Unterminated_string -> 
      hOV 0 [< 'sTR "Syntax error: Unterminated string." >]
  | reraise ->
      hOV 0 [< 'sTR "Anomaly: Uncaught exception "; 
	       'sTR (Printexc.to_string reraise); report () >]

let raise_if_debug e =
  if !Options.debug then raise e

let explain_exn_function = ref explain_exn_default

let explain_exn e = !explain_exn_function e
