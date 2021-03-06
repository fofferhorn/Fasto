structure CopyConstPropFold = struct

(*
    (* An optimisation takes a program and returns a new program. *)
    val optimiseProgram : Fasto.KnownTypes.Prog -> Fasto.KnownTypes.Prog
*)

open Fasto
open Fasto.KnownTypes

exception Error of string * pos

(* A propagatee is something that we can propagate - either a variable
   name or a constant value. *)
datatype Propagatee = ConstProp of Value
                    | VarProp of string

(* extracts an propagatee from an exp, e.g., from exp a it extracts VarProp(a) *)
fun expPropagatee (Var (varname, _)) = SOME (VarProp varname)
| expPropagatee (Constant (value, _)) = SOME (ConstProp value)
 (* goes down on a let body, just as an optimization *)
(* e.g.,let x =... in 3 returns propagatee ConstProp(IntVal 3)*)

(* vtable binds var names to their propagatees (either a value or a var name) *)
fun bindExpPropagatee name e vtable = 
  case expPropagatee e of
       NONE => SymTab.remove name vtable    (* remove any shadowed binding *)
     | SOME prop => SymTab.bind name prop vtable

fun copyConstPropFoldExp vtable e =
    case e of
        Constant x => Constant x
      | StringLit x => StringLit x
      | ArrayLit (es, t, pos) =>
        ArrayLit (map (copyConstPropFoldExp vtable) es, t, pos)
      | Var (name, pos) =>
          (case SymTab.lookup name vtable of
                SOME (VarProp newname) => Var (newname, pos)    (* copy propag *)
              | SOME (ConstProp value) => Constant (value, pos) (* const propag *)
              | _                      => Var (name, pos))      (* no propagation *)
      | Plus (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant (IntVal x, _), Constant (IntVal y, _)) =>
               Constant (IntVal (x+y), pos)
             | (Constant (IntVal 0, _), _) =>
               e2'
             | (_, Constant (IntVal 0, _)) =>
               e1'
             | _ =>
               Plus (e1', e2', pos)
        end
      | Minus (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant (IntVal x, _), Constant (IntVal y, _)) =>
               Constant (IntVal (x-y), pos)
             | (_, Constant (IntVal 0, _)) =>
               e1'
             | _ =>
               Minus (e1', e2', pos)
        end
      | Times (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant (IntVal x, _), Constant (IntVal y, _)) =>
               Constant (IntVal (x*y), pos)
             | (Constant (IntVal 0, _), _) =>
               Constant (IntVal 0, pos)
             | (_, Constant (IntVal 0, _)) =>
               Constant (IntVal 0, pos)
             | (_, Constant (IntVal 1, _)) => e1'
             | (Constant (IntVal 1, _), _) => e2'
             | _ => Times (e1', e2', pos)
        end
      | Divide (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant (IntVal x, _), Constant (IntVal y, _)) => 
               Constant (IntVal (Int.quot(x,y)), pos)

             | (Constant (IntVal 0, _),          _            ) => 
               Constant (IntVal 0, pos)
               
             | _                                                => 
               Divide (e1', e2', pos)
        end
      | Negate (e1, pos) =>
        let
          val e1' = copyConstPropFoldExp vtable e1
        in
          case e1' of
              Constant (IntVal 0, _) => Constant (IntVal 0, pos)
            | Constant (IntVal x, _) => Constant (IntVal (0-x), pos)
            | Negate (e, _)          => e
            | _                      => Negate (e1', pos)
        end 
      | Not (e1, pos) =>
        let
          val e1' = copyConstPropFoldExp vtable e1
        in
          case e1' of
              Constant (BoolVal true, _)  => Constant (BoolVal false, pos)
            | Constant (BoolVal false, _) => Constant (BoolVal true, pos) 
            | Not(e, _)                   => e
            | _                           => Not (e1', pos)
        end 
      | Equal (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant v1, Constant v2) =>
               Constant (BoolVal (v1 = v2), pos)
             | _ => if e1' = e2'
                    then Constant (BoolVal true, pos)
                    else Equal (e1', e2', pos)
        end
      | And (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in 
          case e1' of
                Constant (BoolVal true, pos)  => 
                    (case e2' of
                          Constant (BoolVal true, pos)  => Constant (BoolVal true, pos)
                        | Constant (BoolVal false, pos) => Constant (BoolVal false, pos)
                        | _                             => And (Constant (BoolVal true, pos), e2', pos)
                    )
              | Constant (BoolVal false, pos) => Constant(BoolVal false, pos)
              | _                             => And (e1', e2', pos)
        end
      | Or (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in 
          case e1' of
                Constant (BoolVal false, pos)  => 
                    (case e2' of
                          Constant (BoolVal true, pos)  => Constant (BoolVal true, pos)
                        | Constant (BoolVal false, pos) => Constant (BoolVal false, pos)
                        | _                             => Or (Constant (BoolVal false, pos), e2', pos)
                    )
              | Constant (BoolVal true, pos) => Constant(BoolVal true, pos)
              | _                             => Or (e1', e2', pos)
        end
      | Less (e1, e2, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
            val e2' = copyConstPropFoldExp vtable e2
        in case (e1', e2') of
               (Constant (IntVal v1, _), Constant (IntVal v2, _)) =>
               Constant (BoolVal (v1 < v2), pos)
             | _ => if e1' = e2'
                    then Constant (BoolVal false, pos)
                    else Less (e1', e2', pos)
        end
      | If (e1, e2, e3, pos) =>
        let val e1' = copyConstPropFoldExp vtable e1
        in case e1' of
               Constant (BoolVal b, _) => if b
                                          then copyConstPropFoldExp vtable e2
                                          else copyConstPropFoldExp vtable e2
             | _ => If (copyConstPropFoldExp vtable e1',
                        copyConstPropFoldExp vtable e2,
                        copyConstPropFoldExp vtable e3,
                        pos)
        end
      | Apply (fname, es, pos) =>
        Apply (fname, map (copyConstPropFoldExp vtable) es, pos)
      | Let (Dec (name, e, decpos), body, pos) =>
          let 
            val e'      = copyConstPropFoldExp vtable e     (* optimize e *)
            val vtable' = bindExpPropagatee name e' vtable  (* bind propagatee *)
            val body'   = copyConstPropFoldExp vtable' body (* optimize body *)
          in 
            Let (Dec (name, e', decpos), body', pos)        (* return optimized Let expression *)
          end
      | Index (name, e, t, pos) =>
        let val e' = copyConstPropFoldExp vtable e
        in (* We can only copy-propagate variables for indexing. *)
            case SymTab.lookup name vtable of
                SOME (VarProp newname) => Index (newname, e', t, pos)
              | _ => Index (name, e, t, pos)
        end
      | Iota (e, pos) =>
        Iota (copyConstPropFoldExp vtable e, pos)
      | Map (farg, e, t1, t2, pos) =>
        Map (copyConstPropFoldFunArg vtable farg,
             copyConstPropFoldExp vtable e,
             t1, t2, pos)
      | Reduce (farg, e1, e2, t, pos) =>
        Reduce (copyConstPropFoldFunArg vtable farg,
                copyConstPropFoldExp vtable e1,
                copyConstPropFoldExp vtable e2,
                t, pos)
      | Replicate (e1, e2, t, pos) =>
        Replicate (copyConstPropFoldExp vtable e1,
                   copyConstPropFoldExp vtable e2,
                   t, pos)
      | Filter (farg, e, t, pos) =>
        Filter (copyConstPropFoldFunArg vtable farg,
                copyConstPropFoldExp vtable e,
                t, pos)
      | Scan (farg, e1, e2, t, pos) =>
        Scan (copyConstPropFoldFunArg vtable farg,
              copyConstPropFoldExp vtable e1,
              copyConstPropFoldExp vtable e2,
              t, pos)
      | ArrCompr (e, bs, cs, e_tp, arr_tps, pos) =>
        ArrCompr (copyConstPropFoldExp vtable e,
                  map (fn (n, x) => (n, copyConstPropFoldExp vtable x)) bs,
                  map (copyConstPropFoldExp vtable) cs,
                  e_tp, arr_tps, pos)
      | Read (t, pos) =>
        Read (t, pos)
      | Write (e, t, pos) =>
        Write (copyConstPropFoldExp vtable e, t, pos)

and copyConstPropFoldFunArg vtable (FunName fname) =
    FunName fname
  | copyConstPropFoldFunArg vtable (Lambda (rettype, params, body, pos)) =
    (* Remove any bindings with the same names as the parameters. *)
    let val paramNames = (map (fn (Param (name, _)) => name) params)
        val vtable' = SymTab.removeMany paramNames vtable
    in Lambda (rettype, params, copyConstPropFoldExp vtable' body, pos)
    end

fun copyConstPropFoldFunDec (FunDec (fname, rettype, params, body, loc)) =
    let val body' = copyConstPropFoldExp (SymTab.empty ()) body
    in FunDec (fname, rettype, params, body', loc)
    end

fun optimiseProgram prog =
    map copyConstPropFoldFunDec prog
end
