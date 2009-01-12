(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2008 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

module Term = Lang_values
include Term.V
module T = Lang_types

type kind = T.t

(** Helpers for defining builtin functions. *)

type proto = (string*kind*value option*string option) list

let doc_of_prototype_item t d doc =
  let doc = match doc with None -> "(no doc)" | Some d -> d in
  let item = new Doc.item doc in
    item#add_subsection "type" (Doc.trivial (T.print t)) ;
    item#add_subsection "default"
      (match d with
         | None -> Doc.trivial "None"
         | Some d -> Doc.trivial (print_value d)) ;
    item

type doc_flag = Hidden | Deprecated | Experimental
let string_of_flag = function
  | Hidden -> "hidden"
  | Deprecated -> "deprecated"
  | Experimental -> "experimental"

let builtin_type p t =
  T.make (T.Arrow (List.map (fun (lbl,kind,opt,_) -> (opt<>None,lbl,kind)) p, t))
    
let to_doc category flags main_doc proto return_t =
  let item = new Doc.item ~sort:false main_doc in
  let kind = builtin_type proto return_t in
    item#add_subsection "category" (Doc.trivial category) ;
    item#add_subsection "type" (Doc.trivial (T.print kind)) ;
    List.iter
      (fun f -> item#add_subsection "flag" (Doc.trivial (string_of_flag f)))
      flags;
    List.iter
      (fun (l,t,d,doc) ->
         item#add_subsection
           (if l = "" then "(unlabeled)" else l)
           (doc_of_prototype_item t d doc)) proto ;
    item

let builtin_value p ret_t f =
  { t = builtin_type p ret_t ;
    value = FFI (List.map (fun (lbl,_,opt,_) -> lbl,lbl,opt) p, [], [], f) }

let add_builtin ~category ~descr ?(flags=[]) name proto return_t f =
  let value = builtin_value proto return_t f in
    Term.builtins#register ~doc:(to_doc category flags descr proto return_t)
      name value

(** Specialized version for operators, that is builtins returning sources. *)

type category =
  | Input | Output | TrackProcessing | SoundProcessing | VideoProcessing | Visualization

let string_of_category x = "Source / " ^ match x with
  | Input -> "Input"
  | Output -> "Output"
  | TrackProcessing -> "Track Processing"
  | SoundProcessing -> "Sound Processing"
  | VideoProcessing -> "Video Processing"
  | Visualization -> "Visualization"

let add_operator ~category ~descr ?(flags=[]) name proto f =
  let proto =
    let t = T.make (T.Ground T.String) in
      ("id", t,
       Some { t = t ; value = String "" },
       Some "Force the value of the source ID.")::proto
  in
  let f x =
    let src : Source.source = f x in
    let id =
      match (List.assoc "id" x).value with
        | String s -> s
        | _ -> assert false
    in
      if id <> "" then src#set_id id ;
      { t = T.make (T.Ground T.Source) ;
        value = Source src }
  in
  let return_t = T.make (T.Ground T.Source) in
  let category = string_of_category category in
    add_builtin ~category ~descr ~flags name proto return_t f

let iter_sources f v =
  let rec iter_term env v = match v.Term.term with
    | Term.Source s -> f s
    | Term.Unit | Term.Bool _
    | Term.Int _ | Term.Float _ | Term.String _ | Term.Request _ -> ()
    | Term.List l -> List.iter (iter_term env) l
    | Term.Let (_,_,a,b) | Term.Product (a,b) | Term.Seq (a,b) ->
        iter_term env a ; iter_term env b
    | Term.Var v ->
        (* If it's locally bound it won't be in [env]. *)
        (* TODO since inner-bound variables don't mask outer ones in [env],
         *   we are actually checking values that may be out of reach. *)
        begin try iter_value (List.assoc v env) with Not_found -> () end
    | Term.App (a,l) ->
        iter_term env a ;
        List.iter (fun (_,v) -> iter_term env v) l
    | Term.Fun (proto,body) ->
        iter_term env body ;
        List.iter (fun (_,_,_,v) -> match v with
                     | Some v -> iter_term env v
                     | None -> ()) proto
  and iter_value v = match v.value with
    | Source s -> f s
    | Unit | Bool _ | Int _ | Float _ | String _ | Request _ -> ()
    | List l -> List.iter iter_value l
    | Product (a,b) ->
        iter_value a ; iter_value b
    | Fun (proto,pe,env,body) ->
        iter_term env body ; (* TODO this doesn't sound right/precise *)
        List.iter (fun (_,v) -> iter_value v) pe ;
        List.iter
          (function
             | _,_,Some v -> iter_value v
             | _ -> ())
          proto
    | FFI (proto,pe,env,_) ->
        List.iter (fun (_,v) -> iter_value v) env ;
        List.iter (fun (_,v) -> iter_value v) pe ; (* TODO imprecise *)
        List.iter
          (function
             | _,_,Some v -> iter_value v
             | _ -> ())
          proto
  in
    iter_value v

let apply f p = Term.apply f p

(** {1 High-level manipulation of values} *)

let to_bool t = match t.value with
  | Bool b -> b
  | _ -> assert false

let to_string t = match t.value with
  | String s -> s
  | _ -> assert false

let to_string_getter t = match t.value with
  | String s -> (fun () -> s)
  | Fun _ | FFI _ ->
      (fun () ->
         match (apply t []).value with String s -> s | _ -> assert false)
  | _ -> assert false

let to_float t = match t.value with
  | Float s -> s
  | _ -> assert false

let to_float_getter t = match t.value with
  | Float s -> (fun () -> s)
  | Fun _ | FFI _ ->
      (fun () ->
         match (apply t []).value with Float s -> s | _ -> assert false)
  | _ -> assert false

let to_source t = match t.value with
  | Source s -> s
  | _ -> assert false

let to_request t = match t.value with
  | Request (Some r) -> Some (Request.to_audio r)
  | Request None -> None
  | _ -> assert false

let to_request_raw t = match t.value with
  | Request (Some r) -> Some (Request.to_raw r)
  | Request None -> None
  | _ -> assert false

let to_int t = match t.value with
  | Int s -> s
  | _ -> assert false

let to_list t = match t.value with
  | List l -> l
  | _ -> assert false

let to_product t = match t.value with
  | Product (a,b) -> (a,b)
  | _ -> assert false

let to_metadata t = 
  let pop v = 
    let f (a,b) = (to_string a,to_string b) in
    f (to_product v)
  in
  let t = List.map pop (to_list t) in
  let metas = Hashtbl.create 10 in
  List.iter (fun (a,b) -> Hashtbl.add metas a b) t;
  metas

let to_string_list l = List.map to_string (to_list l)
let to_int_list l = List.map to_int (to_list l)
let to_source_list l = List.map to_source (to_list l)

(** [assoc lbl n l] returns the [n]th element in [l]
  * of which the first component is [lbl]. *)
let rec assoc label n = function
  | [] -> raise Not_found
  | (l,e)::tl ->
       if l = label then
         if n = 1 then
           e
         else
           assoc label (n-1) tl
       else
         assoc label n tl

(** Some shortcuts *)

let ground_t x = T.make (T.Ground x)

let int_t     = ground_t T.Int
let unit_t    = ground_t T.Unit
let float_t   = ground_t T.Float
let bool_t    = ground_t T.Bool
let string_t  = ground_t T.String
let source_t  = ground_t T.Source
let request_t = ground_t T.Request
let list_t t  = T.make (T.List t)
let product_t a b = T.make (T.Product (a,b))
let fun_t p b = T.make (T.Arrow (p,b))
let univ_t ?(constraints=[]) i = T.make (T.UVar (i,constraints))
let metadata_t = list_t (product_t string_t string_t)
let string_getter_t n = univ_t ~constraints:[T.Getter T.String] n
let float_getter_t n = univ_t ~constraints:[T.Getter T.Float] n

let mk v = { t = T.dummy ; value = v }
let unit = mk Unit
let int i = mk (Int i)
let bool i = mk (Bool i)
let float i = mk (Float i)
let string i = mk (String i)
let list l = mk (List l)
let source s = mk (Source s)

(** Warning: this is unsafe, not necessarily really audio. *)
let request r = mk (Request r)
let product a b = mk (Product (a,b))
let val_fun p f = mk (FFI (p,[],[],f))
let val_cst_fun p c =
  let f tm = mk (Fun (p,[],[],{ Term.t = c.t ; Term.term = tm })) in
    match c.value with
      | Unit -> f Term.Unit
      | Int i -> f (Term.Int i)
      | Bool i -> f (Term.Bool i)
      | Float i -> f (Term.Float i)
      | String i -> f (Term.String i)
      | _ -> mk (FFI (p,[],[],fun _ -> c))
let metadata m =
  list (Hashtbl.fold
          (fun k v l -> (product (string k) (string v))::l)
          m [])

(** Runtime error, should eventually disappear. *)
exception Invalid_value of value*string

(** {1 Parsing} *)

let type_and_run ast =
  Term.check ast ;
  ignore (Term.eval_toplevel ast)

let infered_pos a =
  let dpos = (T.deref a).T.pos in
    if a.T.pos = dpos then "" else
      match dpos with
        | None -> ""
        | Some p -> "\n    (infered at " ^ T.print_pos ~prefix:"" p ^ ")"

(* We can't expect one position per item, think of a failed unification
 * between FFI types for example. *)
let rec print_type_error focus_left = function
  | T.Flip::tl -> print_type_error (not focus_left) tl
  | T.Item (a,b)::tl ->
      let (xtype,a,b) =
        if focus_left then ("subtype",a,b) else ("supertype",b,a)
      in
        Printf.printf
          "\n%s:\n  this value has type\n    %s%s\n"
          (match a.T.pos with
             | None -> "At unknown position"
             | Some p -> T.print_pos p)
          (T.print a)
          (infered_pos a) ;
        Printf.printf
          "  but it should be a %s of%s\n    %s%s\n%!"
          xtype
          (match b.T.pos with
             | None -> ""
             | Some p ->
                 Printf.sprintf " (the type of the value at %s)"
                   (T.print_pos ~prefix:"" p))
          (T.print b)
          (infered_pos b) ;
        print_type_error focus_left tl
  | [] -> ()

let print_type_error trace = print_type_error true trace

let from_in_channel ?(parse_only=false) ~ns stdin =
  let lexbuf = Lexing.from_channel stdin in
  let print_error error =
    flush_all () ;
    let start = lexbuf.Lexing.lex_curr_p in
      Printf.printf "%sine %d, char %d"
        (if start.Lexing.pos_fname="" then "L" else
           Printf.sprintf "File %S, l" start.Lexing.pos_fname)
        start.Lexing.pos_lnum
        (1+start.Lexing.pos_cnum-start.Lexing.pos_bol) ;
      if Lexing.lexeme lexbuf = "" then
        Printf.printf ": %s\n" error
      else
        Printf.printf
          " before %S: %s.\n" (Lexing.lexeme lexbuf) error
  in
    assert (lexbuf.Lexing.lex_start_p = lexbuf.Lexing.lex_curr_p) ;
    begin match ns with
      | Some ns ->
          lexbuf.Lexing.lex_start_p <- { lexbuf.Lexing.lex_start_p with
                                             Lexing.pos_fname = ns } ;
          lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with
                                             Lexing.pos_fname = ns }
      | None -> ()
    end ;
    try
      (if parse_only then ignore else type_and_run)
        (Lang_parser.scheduler Lang_pp.token lexbuf)
    with
      | Failure "lexing: empty token" -> print_error "Empty token" ; exit 1
      | Parsing.Parse_error -> print_error "Parse error" ; exit 1
      | Term.Unbound (pos,s) ->
          let pos = T.print_pos (Utils.get_some pos) in
            Printf.printf
              "%s: unbound symbol %s.\n" pos s ;
            exit 1
      | T.Error trace ->
          flush_all () ;
          Printf.printf "ERROR: This script is not well typed!\n" ;
          print_type_error trace ;
          exit 1
      | Term.No_label (f,lbl,first,x) ->
          let pos_f =
            T.print_pos ~prefix:"at " (Utils.get_some f.Term.t.T.pos)
          in
          let pos_x = T.print_pos (Utils.get_some x.Term.t.T.pos) in
            flush_all () ;
            Printf.printf "ERROR: This script is not well typed!\n" ;
            Printf.printf
              "\n%s: cannot apply that parameter because the function (%s) "
              pos_x pos_f ;
            Printf.printf
              "has %s %s!\n"
              (if first then "no" else "no more")
              (if lbl="" then "unlabeled argument" else
                 Printf.sprintf "argument labeled %S" lbl) ;
            exit 1
      | Invalid_value (v,msg) ->
          Printf.printf
            "%s: %s.\n"
            (T.print_pos ~prefix:"Invalid value at "
               (Utils.get_some v.t.T.pos))
            msg ;
          exit 1
      | e -> print_error "Unknown error" ; raise e

let from_file ?parse_only ~ns filename =
  let ic = open_in filename in
    from_in_channel ?parse_only ~ns ic ;
    close_in ic

let load_libs ?parse_only () =
  let dir = Configure.libs_dir in
    Array.iter
      (fun file ->
        if Filename.check_suffix file ".liq" then
          from_file ?parse_only
            ~ns:(Some (Filename.basename file)) (dir^"/"^file))
      (try Sys.readdir dir with _ -> [||])

let from_file = from_file ~ns:None

let from_string ?parse_only expr =
  let i,o = Unix.pipe () in
  let i = Unix.in_channel_of_descr i in
  let o = Unix.out_channel_of_descr o in
    output_string o expr ;
    close_out o ;
    from_in_channel ?parse_only ~ns:None i ;
    close_in i

let from_in_channel ?parse_only x =
  from_in_channel ?parse_only ~ns:None x