open Utility

module Cs = struct

  type offset = int
  type cs = csentry list
  and csentry =
    | Offset of offset
    | Mapping of string * cs

  let rec leafs cs =
    List.rev
      (List.fold_left
	 (fun leaf_list cs_entry ->
	    match cs_entry with
	      | Offset o -> o :: leaf_list
	      | Mapping (_, cs) -> (List.rev (leafs cs)) @ leaf_list)
	 []
	 cs)

  let cardinality = List.length

  let rec shift cs i =
    List.map
      (function
	 | Offset o -> Offset (o + i)
	 | Mapping (key, cs) -> Mapping (key, (shift cs i)))
      cs

  let append cs1 cs2 =
    cs1 @ (shift cs2 (cardinality cs1))

  let fuse cs1 cs2 =
    if (List.length cs1) > (List.length cs2) then
      cs1
    else
      cs2

  let is_operand cs =
    if List.length cs <> 1 then
      false
    else
      match (List.hd cs) with
	| Offset _ -> true
	| _ -> false

  let record_field cs field =
    let rec loop = function
      | (Offset _) :: tl ->
	  loop tl
      | (Mapping (key, cs)) :: tl ->
	  if key = field then
	    cs
	  else
	    loop tl
      | [] ->
	  failwith "Cs.get_mapping: unknown field name"
    in
      loop cs
end

module A = Algebra
module AEnv = Env.Int

type tblinfo = A.Dag.dag ref * Cs.cs * unit * unit
type aenv = tblinfo AEnv.t

let dummy = ()

let incr l i = List.map (fun j -> j + i) l
let items_of_offsets = List.map (fun i -> A.Item i)

let proj1 col = (col, col)

let proj_list = List.map proj1

let proj_list_map new_cols old_cols = 
  List.map2 (fun a b -> (a, b)) new_cols old_cols

let wrap_1to1 f res c c' algexpr =
  A.Dag.mk_fun1to1
    (f, res, [c; c'])
    algexpr

let wrap_eq res c c' algexpr =
  A.Dag.mk_funnumeq
    (res, (c, c'))
    algexpr

let incr_col = function
  | A.Iter i -> A.Iter (i + 1)
  | A.Pos i -> A.Pos (i + 1)
  | A.Item i -> A.Item (i + 1)

let wrap_ne res c c' algexpr =
  let res' = incr_col res in
    A.Dag.mk_funboolnot
      (res, res')
      (ref (A.Dag.mk_funnumeq
	      (res', (c, c'))
	      algexpr))

let wrap_gt res c c' algexpr =
  A.Dag.mk_funnumgt
    (res, (c, c'))
    algexpr

let wrap_not res op_attr algexpr =
  A.Dag.mk_funboolnot
    (res, op_attr)
    algexpr

(* the empty list *)
let nil = ref (A.Dag.mk_emptytbl [(A.Iter 0, A.NatType); (A.Pos 0, A.NatType)])

let map_inwards map (q, cs, _, _) =
  let iter = A.Iter 0 in
  let inner = A.Iter 1 in
  let outer = A.Iter 2 in
  let pos = A.Pos 0 in
  let q' =
    (ref (A.Dag.mk_project
	    ([(iter, inner); proj1 pos] @ (proj_list (items_of_offsets (Cs.leafs cs))))
	    (ref (A.Dag.mk_eqjoin
		    (iter, outer)
		    q
		    map))))
  in
    (q', cs, dummy, dummy)

let rec compile_append env loop l =
  match l with
    | e :: [] ->
	compile_expression env loop e
    | hd_e :: tl_e ->
	let hd = compile_expression env loop hd_e in
	let tl = compile_append env loop tl_e in
	  compile_list hd tl
    | [] ->
	(nil, [], dummy, dummy)

and compile_list (hd_q, hd_cs, _, _) (tl_q, tl_cs, _, _) =
  let fused_cs = Cs.fuse hd_cs tl_cs in
  let ord = A.Pos 2 in
  let pos = A.Pos 0 in
  let pos' = A.Pos 1 in
  let iter = A.Iter 0 in
  let q =
    ref (A.Dag.mk_project
	   ((proj1 iter) :: ((pos, pos') :: proj_list (items_of_offsets (Cs.leafs (fused_cs)))))
	   (ref (A.Dag.mk_rank
		   (pos', [(ord, A.Ascending); (pos, A.Ascending)])
		   (ref (A.Dag.mk_disjunion
			   (ref (A.Dag.mk_attach
				   (ord, A.Nat 1n)
				   hd_q))
			   (ref (A.Dag.mk_attach
				   (ord, A.Nat 2n)
				   tl_q)))))))
  in
    (q, fused_cs, dummy, dummy)

and compile_binop env loop wrapper operands =
  assert ((List.length operands) = 2);
  let (op1_q, op1_cs, _, _) = compile_expression env loop (List.hd operands) in
  let (op2_q, op2_cs, _, _) = compile_expression env loop (List.nth operands 1) in
    assert (Cs.is_operand op1_cs);
    assert (Cs.is_operand op2_cs);
    let iter = A.Iter 0 in
    let iter' = A.Iter 1 in
    let pos = A.Pos 0 in
    let c = A.Item 1 in
    let c' = A.Item 2 in
    let res = A.Item 3 in
    let q = 
      ref (A.Dag.mk_project
	     [(proj1 iter); (proj1 pos); (c, res)]
	     (ref (wrapper 
		     res c c'
		     (ref (A.Dag.mk_eqjoin
			     (iter, iter')
			     op1_q
			     (ref (A.Dag.mk_project
				     [(iter', iter); (c', c)]
				     op2_q)))))))
    in
      (q, op1_cs, dummy, dummy)

and compile_unop env loop wrapper operands =
  assert ((List.length operands) = 1);
  let (op_q, op_cs, _, _) = compile_expression env loop (List.hd operands) in
    assert (Cs.is_operand op_cs);
    let c = A.Item 1 in
    let res = A.Item 2 in
    let pos = A.Pos 0 in
    let iter = A.Iter 0 in
    let q = 
      ref (A.Dag.mk_project
	     [proj1 iter; proj1 pos; (c, res)]
	     (ref (wrapper
		     res c
		     op_q)))
    in
      (q, op_cs, dummy, dummy)

and compile_apply env loop f args =
  match f with
    | "+" 
    | "+." -> compile_binop env loop (wrap_1to1 A.Add) args
    | "-" 
    | "-." -> compile_binop env loop (wrap_1to1 A.Subtract) args
    | "*"
    | "*." -> compile_binop env loop (wrap_1to1 A.Multiply) args
    | "/" 
    | "/." -> compile_binop env loop (wrap_1to1 A.Divide) args
    | "==" -> compile_binop env loop wrap_eq args
    | ">" -> compile_binop env loop wrap_gt args
    | "<" -> compile_binop env loop wrap_gt (List.rev args)
    | "<>" -> compile_binop env loop wrap_ne args
    | "not" -> compile_unop env loop wrap_not args
    | ">="
    | "<="
    | _ ->
	failwith "CompileQuery.op_dispatch: not implemented"
	  (*
	    | `PrimitiveFunction "Concat" ->
	    | `PrimitiveFunction "take" ->
	    | `PrimitiveFunction "drop" ->
	    | `PrimitiveFunction "max" ->
	    | `PrimitiveFunction "min" ->
	    | `PrimitiveFunction "hd" ->
	    | `PrimitiveFunction "tl" ->
	  *)


and compile_for env loop v e1 e2 =
  let iter = A.Iter 0 in
  let inner = A.Iter 1 in
  let outer = A.Iter 2 in
  let pos = A.Pos 0 in
  let pos' = A.Pos 1 in
  let (q1, cs1, _, _) = compile_expression env loop e1 in
  let q_v = 
    ref (A.Dag.mk_rownum
	   (inner, [(iter, A.Ascending); (pos, A.Ascending)], None)
	   q1)
  in
  let map =
    ref (A.Dag.mk_project
	   [(outer, iter); proj1 inner]
	   q_v)
  in
  let loop_v =
    ref (A.Dag.mk_project
	   [(iter, inner)]
	   q_v)
  in
  let q_v' =
    ref (A.Dag.mk_attach
	   (pos, A.Nat 1n)
	   (ref (A.Dag.mk_project
		   ([(iter, inner)] @ (proj_list (items_of_offsets (Cs.leafs cs1))))
		   q_v)))
  in
  let env = AEnv.map (map_inwards map) env in
  let (q2, cs2, _, _) = compile_expression (AEnv.bind env (v, (q_v', cs1, dummy, dummy))) loop_v e2 in
  let q =
    ref (A.Dag.mk_project
	   ([(iter, outer); (pos, pos')] @ (proj_list (items_of_offsets (Cs.leafs cs2))))
	   (ref (A.Dag.mk_rank
		   (pos', [(iter, A.Ascending); (pos, A.Ascending)])
		   (ref (A.Dag.mk_eqjoin
			   (inner, iter)
			   map
			   q2)))))
  in
    (q, cs2, dummy, dummy)

and singleton_record env loop (name, e) =
  let (q, cs, _, _) = compile_expression env loop e in
    (q, [Cs.Mapping (name, cs)], dummy, dummy)

and extend_record env loop ext_fields r =
  assert (match ext_fields with [] -> false | _ -> true);
  match ext_fields with
    | (name, e) :: [] -> 
	(match r with 
	   | Some record ->
	       merge_records (singleton_record env loop (name, e)) record
	   | None ->
	       singleton_record env loop (name, e))
    | (name, e) :: tl ->
	let new_field = singleton_record env loop (name, e) in
	let record = extend_record env loop tl r in
	  merge_records new_field record
    | [] ->
	failwith "CompileQuery.extend_record: empty ext_fields"

and merge_records (r1_q, r1_cs, _, _) (r2_q, r2_cs, _, _) =
  let r2_leafs = Cs.leafs r2_cs in
  let new_names_r2 = items_of_offsets (incr r2_leafs (Cs.cardinality r1_cs)) in
  let old_names_r2 = items_of_offsets r2_leafs in
  let names_r1 = items_of_offsets (Cs.leafs r1_cs) in
  let iter = A.Iter 0 in
  let iter' = A.Iter 1 in
  let q =
    ref (A.Dag.mk_project
	   (proj_list ([A.Iter 0; A.Pos 0] @ names_r1 @ new_names_r2))
	   (ref (A.Dag.mk_eqjoin
		   (iter, iter')
		   r1_q
		   (ref ((A.Dag.mk_project
			    ((iter', iter) :: (proj_list_map new_names_r2 old_names_r2))
			    r2_q))))))
  in
  let cs = Cs.append r1_cs r2_cs in
    (q, cs, dummy, dummy)

and compile_project env loop field r =
  let (q_r, cs_r, _, _) = compile_expression env loop r in
  let field_cs' = Cs.record_field cs_r field in
  let c_old = Cs.leafs field_cs' in
  let offset = List.hd c_old in
  let c_new = incr c_old (-offset + 1) in
  let field_cs = Cs.shift field_cs' (-offset + 1) in
  let iter = A.Iter 0 in
  let pos = A.Pos 0 in
  let q =
    ref (A.Dag.mk_project
	   ([proj1 iter; proj1 pos] @ proj_list_map (items_of_offsets c_new) (items_of_offsets c_old))
	   q_r)
  in
    (q, field_cs, dummy, dummy)

and compile_record env loop r =
  match r with
    | (name, value) :: [] ->
	singleton_record env loop (name, value)
    | (name, value) :: tl ->
	let f = singleton_record env loop (name, value) in
	  merge_records f (compile_record env loop tl)
    | [] ->
	failwith "CompileQuery.compile_record_value: empty record"

(* HACK HACK HACK: rewrite this when Value.table stores key information *)
and compile_table loop ((_db, _params), tblname, _row) =
  Printf.printf "tblname = %s\n" tblname;
  flush stdout;
  assert (tblname = "test1");
  let columns = ["foo"; "bar"] in
  let items = snd (List.fold_left (fun (i, l) c -> (i + 1, (c, A.Item i) :: l)) (1, []) columns) in
  let cs = List.map (function (tname, A.Item i) -> Cs.Mapping (tname, [Cs.Offset i]) | _ -> assert false) items in
  let pos = A.Pos 0 in
  let key_infos = [[A.Item 1]] in
  let attr_infos = List.map (fun (tname, name) -> (name, tname, A.IntType)) items in
  let q =
    ref (A.Dag.mk_cross
	   loop
	   (ref (A.Dag.mk_rank
		   (pos, (List.map (fun (_, name) -> (name, A.Ascending)) items))
		   (ref (A.Dag.mk_tblref
			   (tblname, attr_infos, key_infos))))))
  in
    (q, cs, dummy, dummy)

and compile_constant loop (c : Constant.constant) =
  let cs = [Cs.Offset 1] in
  let q =
    (ref (A.Dag.mk_attach
	    (A.Item 1, A.const c)
	    (ref (A.Dag.mk_attach
		    (A.Pos 0, A.Nat 1n)
		    loop))))
  in
    (q, cs, dummy, dummy)

and compile_if env loop e1 e2 e3 =
  let iter = A.Iter 0 in
  let pos = A.Pos 0 in
  let iter' = A.Iter 1 in
  let c = A.Item 1 in
  let res = A.Item 2 in
    
  let select loop (q, cs, _, _) =
    let cols = items_of_offsets (Cs.leafs cs) in
      let q' =
	ref (A.Dag.mk_project
	   ([proj1 iter; proj1 pos] @ (proj_list cols))
	   (ref (A.Dag.mk_eqjoin
		   (iter, iter')
		   q
		   (ref (A.Dag.mk_project
			   [(iter', iter)]
			   loop)))))
      in
	(q', cs, dummy, dummy)
  in
  (* condition *)
  let (q_e1, cs_e1, _, _) = compile_expression env loop e1 in
    assert (Cs.is_operand cs_e1);
    let loop_then =
      ref (A.Dag.mk_project
	     [proj1 iter]
	     (ref (A.Dag.mk_select
		     c
		     q_e1)))
    in
      let loop_else =
	ref (A.Dag.mk_project
	       [proj1 iter]
	       (ref (A.Dag.mk_select
		       res
		       (ref (A.Dag.mk_funboolnot
			       (res, c)
			       q_e1)))))
      in
      let env_then = AEnv.map (select loop_then) env in
      let env_else = AEnv.map (select loop_else) env in
      let (q_e2, cs_e2, _, _) = compile_expression env_then loop_then e2 in
      let (q_e3, _cs_e3, _, _) = compile_expression env_else loop_else e3 in
      let q =
	ref (A.Dag.mk_disjunion
	       q_e2
	       q_e3)
      in
	(q, cs_e2, dummy, dummy)

and compile_expression env loop e : tblinfo =
  match e with
    | `Constant c -> compile_constant loop c
    | `Apply (f, args) -> compile_apply env loop f args
    | `Var x -> AEnv.lookup env x
    | `Project (r, field) -> compile_project env loop field r
    | `Record r -> compile_record env loop (StringMap.to_alist r)
    | `Extend (r, ext_fields) ->
	let ext_fields = StringMap.to_alist ext_fields in
	  extend_record env loop ext_fields (opt_map (compile_expression env loop) r)
    | `Singleton e -> compile_expression env loop e
    | `Append l -> compile_append env loop l
    | `Table t -> compile_table loop t
    | `If (c, t, e) -> compile_if env loop c t e
    | `For ([x, l], [], body) -> compile_for env loop x l body
    | `For _ -> failwith "compile_expression: only simple for implemented"

    | `Erase _
    | `Closure _
    | `Variant _
    | `XML _ -> failwith "compile_expression: not implemented"
    | `Primitive _ -> failwith "compile_expression: eval error"

let compile e =
  let loop = 
    (ref (A.Dag.mk_littbl
	    ([[A.Nat 1n]], [(A.Iter 0, A.NatType)])))
  in
  let (q, cs, _, _) = compile_expression AEnv.empty loop e in
  let dag = 
    A.Dag.mk_serializerel 
      (A.Iter 0, A.Pos 0, items_of_offsets (Cs.leafs cs))
      (ref (A.Dag.mk_nil))
      q
  in
    A.Dag.export_plan "plan.xml" (ref dag)