(*
  This file is part of the verified smart contract project of SECBIT Labs.

  Copyright 2018 SECBIT Labs

  Author: Haozhong Zhang

  This program is free software: you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public License
  as published by the Free Software Foundation, either version 3 of
  the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*)

Require Import Arith.
Require Import Nat.
Require Import String.
Open Scope string_scope.

(* XXX: shall Model.event and .state be generated from solidity? *)
Require Import Model.

(* All notations are defined in dsl_scope. *)
Delimit Scope dsl_scope with dsl.

(* *************** *)
(* DSL definitions *)
(* *************** *)

(* Definition of the primitive DSL statements *)
Inductive PrimitiveStmt :=
| DSL_require (cond: state -> env -> message -> bool)
| DSL_emit (evt: state -> env -> message -> event)
| DSL_balances_upd (addr: state -> env -> message -> address)
                   (expr: state -> env -> message -> uint256)
| DSL_allowed_upd (from: state -> env -> message -> address)
                  (to: state -> env -> message -> address)
                  (expr: state -> env -> message -> uint256)
| DSL_totalSupply_upd (expr: state -> env -> message -> uint256)
| DSL_name_upd (expr: state -> env -> message -> string)
| DSL_decimals_upd (expr: state -> env -> message -> uint8)
| DSL_symbol_upd (expr: state -> env -> message -> string)
| DSL_paused_upd (switch: state -> env-> message -> bool)
| DSL_owner_upd (owner: state -> env -> message -> address)
| DSL_return (T: Type) (expr: state -> env -> message -> T)
| DSL_ctor
| DSL_nop.
Arguments DSL_return [T].

(* Definition of DSL statements *)
Inductive Stmt :=
| DSL_prim (stmt: PrimitiveStmt)
| DSL_if (cond: state -> env -> message -> bool) (then_stmt: Stmt) (else_stmt: Stmt)
| DSL_seq (stmt: Stmt) (stmt': Stmt).

(* Result of statement execution *)
Record Result: Type :=
  mk_result {
      ret_st: state;        (* ending state *)
      ret_evts: eventlist;  (* generated events *)
      ret_stopped: bool;    (* does the execution have to stop? *)
    }.
(* Shortcut definition of Result that the execution can continue *)
Definition Next (st: state) (evts: eventlist) : Result :=
  mk_result st evts false.
(* Shortcut definition of Result that the execution has to stop *)
Definition Stop (st: state) (evts: eventlist) : Result :=
  mk_result st evts true.

(* Semantics of the primitive DSL statements *)
Fixpoint dsl_exec_prim
         (stmt: PrimitiveStmt)
         (st0: state)
         (st: state)
         (env: env) (msg: message) (this: address)
         (evts: eventlist): Result :=
  match stmt with
  | DSL_require cond =>
    if cond st env msg then
      Next st evts
    else
      Stop st0 (ev_revert this :: nil)

  | DSL_emit evt =>
    Next st (evts ++ (evt st env msg :: nil))

  | DSL_return expr =>
    Stop st (evts ++ (ev_return _ (expr st env msg) :: nil))

  | DSL_balances_upd addr expr =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st $+ { (addr st env msg) <- (expr st env msg) })
                (st_allowed st)
                (st_paused st)
                (st_owner st))
         evts

  | DSL_allowed_upd from to expr =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st)
                (aa2v_upd_2 (st_allowed st) (from st env msg) (to st env msg) (expr st env msg))
                (st_paused st)
                (st_owner st))
         evts

  | DSL_totalSupply_upd expr =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (st_decimals st)
                (expr st env msg)
                (st_balances st)
                (st_allowed st)
                (st_paused st)
                (st_owner st))
         evts

  | DSL_name_upd expr =>
    Next (mk_st (st_symbol st)
                (expr st env msg)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st)
                (st_allowed st)
                (st_paused st)
                (st_owner st))
         evts

  | DSL_decimals_upd expr =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (expr st env msg)
                (st_totalSupply st)
                (st_balances st)
                (st_allowed st)
                (st_paused st)
                (st_owner st))
         evts

  | DSL_symbol_upd expr =>
    Next (mk_st (expr st env msg)
                (st_name st)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st)
                (st_allowed st)
                (st_paused st)
                (st_owner st))
         evts

  | DSL_owner_upd owner =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st)
                (st_allowed st)
                (st_paused st)
                (owner st env msg))
         evts

  | DSL_paused_upd switch =>
    Next (mk_st (st_symbol st)
                (st_name st)
                (st_decimals st)
                (st_totalSupply st)
                (st_balances st)
                (st_allowed st)
                (switch st env msg)
                (st_owner st))
         evts

  | DSL_ctor =>
    Next st
         (evts ++ (ev_PausableToken (this)
                                    (st_totalSupply st)
                                    (st_name st)
                                    (st_decimals st)
                                    (st_symbol st) :: nil))

  | DSL_nop =>
    Next st evts
  end.

(* Semantics of DSL statements *)
Fixpoint dsl_exec
         (stmt: Stmt)
         (st0: state)
         (st: state)
         (env: env) (msg: message) (this: address)
         (evts: eventlist) {struct stmt}: Result :=
  match stmt with
  | DSL_prim stmt' =>
    dsl_exec_prim stmt' st0 st env msg this evts

  | DSL_if cond then_stmt else_stmt =>
    if cond st env msg then
      dsl_exec then_stmt st0 st env msg this evts
    else
      dsl_exec else_stmt st0 st env msg this evts

  | DSL_seq stmt stmt' =>
    match dsl_exec stmt st0 st env msg this evts with
    | mk_result st'' evts'' stopped  =>
      if stopped then
        mk_result st'' evts'' stopped
      else
        dsl_exec stmt' st0 st'' env msg this evts''
    end
  end.

(* ************************************************************** *)
(* Optional notations that makes the DSL syntax close to Solidity *)
(* ************************************************************** *)

(* Notations for state variables (XXX: shall they be generated from solidity?) *)
Notation "'symbol'" :=
  (fun (st: state) (env: env) (msg: message) => st_symbol st) : dsl_scope.

Notation "'name'" :=
  (fun (st: state) (env: env) (msg: message) => st_name st) : dsl_scope.

Notation "'decimals'" :=
  (fun (st: state) (env: env) (msg: message) => st_decimals st) : dsl_scope.

Notation "'totalSupply'" :=
  (fun (st: state) (env: env) (msg: message) => st_totalSupply st) : dsl_scope.

Notation "'balances'" :=
  (fun (st: state) (env: env) (msg: message) => st_balances st) : dsl_scope.

Definition dsl_balances_access (addr: state -> env -> message -> address) :=
  fun (st: state) (env: env) (msg: message) =>
    (balances%dsl st env msg) (addr st env msg).
Notation "'balances' '[' addr ']'" :=
  (dsl_balances_access addr): dsl_scope.

Notation "'allowed'" :=
  (fun (st: state) (env: env) (msg: message) => st_allowed st) : dsl_scope.

Definition dsl_allowed_access (from to: state -> env -> message -> address) :=
  fun (st: state) (env: env) (msg: message) =>
    (allowed%dsl st env msg) ((from st env msg), (to st env msg)).
Notation "'allowed' '[' from ']' '[' to ']'" :=
  (dsl_allowed_access from to): dsl_scope.

Notation "'owner'" :=
  (fun (st: state) (env: env) (msg: message) => st_owner st) : dsl_scope.

Notation "'paused'" :=
  (fun (st: state) (env: env) (msg: message) => st_paused st) : dsl_scope.

(* Notations for events (XXX: shall they be generated from solidity?) *)
Notation "'Transfer' '(' from ',' to ',' value ')'" :=
  (fun (st: state) (env: env) (msg: message) =>
     ev_Transfer (m_sender msg) (from st env msg) (to st env msg) (value st env msg))
    (at level 210): dsl_scope.

Notation "'Approval' '(' _owner ',' spender ',' value ')'" :=
  (fun (st: state) (env: env) (msg: message) =>
     ev_Approval (m_sender msg) (_owner st env msg) (spender st env msg) (value st env msg))
    (at level 210): dsl_scope.

Notation "'Pause' '(' ')'" :=
  (fun (st: state) (env: env) (msg: message) =>
       ev_Pause)
    (at level 210): dsl_scope.

Notation "'Unpause' '(' ')'" :=
  (fun (st: state) (env: env) (msg: message) =>
       ev_Unpause)
    (at level 210): dsl_scope.

(* Notations for solidity expressions *)
Definition dsl_ge :=
  fun x y (st: state) (env: env) (msg: message) =>
    (negb (ltb (x st env msg) (y st env msg))).
Infix ">=" := dsl_ge : dsl_scope.

Definition dsl_lt :=
  fun x y (st: state) (env: env) (msg: message) =>
    ltb (x st env msg) (y st env msg).
Infix "<" := dsl_lt : dsl_scope.

Definition dsl_le :=
  fun x y (st: state) (env: env) (msg: message) =>
    Nat.leb (x st env msg) (y st env msg).
Infix "<=" := dsl_le : dsl_scope.

Definition dsl_eq :=
  fun x y (st: state) (env: env) (msg: message) =>
    (Nat.eqb (x st env msg) (y st env msg)).
Infix "==" := dsl_eq (at level 70): dsl_scope.

Definition dsl_add  :=
  fun x y (st: state) (env: env) (msg: message) =>
    plus_with_overflow (x st env msg) (y st env msg).
Infix "+" := dsl_add : dsl_scope.

Definition dsl_sub :=
  fun x y (st: state) (env: env) (msg: message) =>
    minus_with_underflow (x st env msg) (y st env msg).
Infix "-" := dsl_sub : dsl_scope.

Definition dsl_or :=
  fun x y (st: state) (env: env) (msg: message) =>
    (orb (x st env msg) (y st env msg)).
Infix "||" := dsl_or : dsl_scope.

Definition dsl_not :=
  fun x (st: state) (env: env) (msg: message) =>
    (negb (x st env msg)).
Notation "'!' x" := (dsl_not x) (at level 75, right associativity) : dsl_scope.

Notation "'msg.sender'" :=
  (fun (st: state) (env: env) (msg: message) =>
     m_sender msg) : dsl_scope.

Definition o0 := 0.

Notation "'0'" :=
  (fun (st: state) (env: env) (msg: message) => 0) : dsl_scope.

Definition otrue := true.
Definition ofalse := false.

Notation "'true'" :=
  (fun (st: state) (env: env) (msg: message) => true) : dsl_scope.
Notation "'false'" :=
  (fun (st: state) (env: env) (msg: message) => false) : dsl_scope.

Notation "'require' '(' cond ')'" :=
  (DSL_require cond) (at level 200) : dsl_scope.
Notation "'emit' evt" :=
  (DSL_emit evt) (at level 200) : dsl_scope.
Notation "'balances' '[' addr ']' '=' expr" :=
  (DSL_balances_upd addr expr) (at level 0) : dsl_scope.
Notation "'balances' '[' addr ']' '+=' expr" :=
  (DSL_balances_upd addr
                    (dsl_add (dsl_balances_access addr) expr))
    (at level 0) : dsl_scope.
Notation "'balances' '[' addr ']' '-=' expr" :=
  (DSL_balances_upd addr
                    (dsl_sub (dsl_balances_access addr) expr))
    (at level 0) : dsl_scope.
Notation "'allowed' '[' from ']' '[' to ']' '=' expr" :=
  (DSL_allowed_upd from to expr) (at level 0) : dsl_scope.
Notation "'allowed' '[' from ']' '[' to ']' '+=' expr" :=
  (DSL_allowed_upd from to
                   (dsl_add (dsl_allowed_access from to) expr))
    (at level 0) : dsl_scope.
Notation "'allowed' '[' from ']' '[' to ']' '-=' expr" :=
  (DSL_allowed_upd from to
                   (dsl_sub (dsl_allowed_access from to) expr))
    (at level 0) : dsl_scope.
Notation "'totalSupply' '=' expr" :=
  (DSL_totalSupply_upd expr) (at level 0) : dsl_scope.
Notation "'totalSupply' '-=' expr" :=
  (DSL_totalSupply_upd (dsl_sub totalSupply%dsl expr)) (at level 0) : dsl_scope.
Notation "'symbol' '=' expr" :=
  (DSL_symbol_upd expr) (at level 0) : dsl_scope.
Notation "'name' '=' expr" :=
  (DSL_name_upd expr) (at level 0) : dsl_scope.
Notation "'decimals' '=' expr" :=
  (DSL_decimals_upd expr) (at level 0) : dsl_scope.
Notation "'owner' '=' expr" :=
  (DSL_owner_upd expr) (at level 0) : dsl_scope.
Notation "'paused' '=' expr" :=
  (DSL_paused_upd expr) (at level 0) : dsl_scope.
Notation "'return' expr" :=
  (DSL_return expr) (at level 200) : dsl_scope.
Notation "'nop'" :=
  (DSL_nop) (at level 200) : dsl_scope.
Notation "'ctor'" :=
  DSL_ctor (at level 200) : dsl_scope.

Notation "@ stmt_prim" :=
  (DSL_prim stmt_prim) (at level 200) : dsl_scope.

Notation "'@if' ( cond ) { stmt0 } 'else' { stmt1 }" :=
  (DSL_if cond stmt0 stmt1) (at level 210) : dsl_scope.

Notation "stmt0 ';' stmt1" :=
  (DSL_seq stmt0 stmt1) (at level 220) : dsl_scope.

Notation "'@uint256' x = expr ; stmt" :=
  (let x: state -> env -> message -> uint256 := expr in stmt)
    (at level 230, x ident) : dsl_scope.

Notation "'@address' x = expr ; stmt" :=
  (let x: state -> env -> message -> address := expr in stmt)
    (at level 230, x ident) : dsl_scope.

Notation "'@uint8' x = expr ; stmt" :=
  (let x: state -> env -> message -> uint8 := expr in stmt)
    (at level 230, x ident) : dsl_scope.

Notation "'@string' x = expr ; stmt" :=
  (let x: state -> env -> message -> string := expr in stmt)
    (at level 230, x ident) : dsl_scope.

(* *************************************************************** *)
(* Each section below represents a ERC20 function in DSL and prove *)
(* the DSL representation does implement the specification.        *)
(* *************************************************************** *)

Require Import Spec.

Section dsl_transfer_from.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{from: state -> env -> message -> address}.
  Context `{_from: address}.
  Context `{to: state -> env -> message -> address}.
  Context `{_to: address}.
  Context `{value: state -> env -> message -> uint256}.
  Context `{_value: uint256}.

  Context `{max_uint256: state -> env -> message -> uint256}.

  (* Arguments are immutable, generated from solidity *)
  Context `{from_immutable: forall st env msg, from st env msg = _from}.
  Context `{to_immutable: forall st env msg, to st env msg = _to}.
  Context `{value_immutable: forall st env msg, value st env msg = _value}.
  Context `{value_in_range: (_value >= 0 /\ _value <= MAX_UINT256)%nat}.
  Context `{max_uint256_immutable: forall st env msg, max_uint256 st env msg = MAX_UINT256}.

  (* DSL representation of transferFrom(), generated from solidity *)
  Definition transferFrom_dsl : Stmt :=
    (@uint256 allowance = allowed[from][msg.sender] ;
     @require(!paused) ;
     @require(balances[from] >= value) ;
     @require((from == to) || (balances[to] <= max_uint256 - value)) ;
     @require(allowance >= value) ;
     @balances[from] -= value ;
     @balances[to] += value ;
     @if (allowance < max_uint256) {
         (@allowed[from][msg.sender] -= value)
     } else {
         (@nop)
     } ;
     (@emit Transfer(from, to, value)) ;
     (@return true)).

  (* Auxiliary lemmas *)
  Lemma nat_nooverflow_dsl_nooverflow:
    forall (m: state -> a2v) st env msg,
      (_from = _to \/ (_from <> _to /\ (m st _to <= MAX_UINT256 - _value)))%nat ->
      ((from == to) ||
       ((fun st env msg => m st (to st env msg)) <= max_uint256 - value))%dsl st env msg = otrue.
  Proof.
    intros m st env msg Hnat.

    unfold "=="%dsl, "<="%dsl, "||"%dsl, "||"%bool, "-"%dsl.
    rewrite (from_immutable st env msg),
            (to_immutable st env msg),
            (value_immutable st env msg),
            (max_uint256_immutable st env msg).
    destruct Hnat.
    - rewrite H. rewrite (Nat.eqb_refl _). reflexivity.
    - destruct H as [Hneq Hle].
      apply Nat.eqb_neq in Hneq. rewrite Hneq.
      apply Nat.leb_le in Hle.
      destruct value_in_range as [_ Hvalue].
      assert (Hlo: (MAX_UINT256 >= _value)%nat);
        auto.
      rewrite (minus_safe _ _ Hlo).
      exact Hle.
  Qed.

  (* Manually proved *)
  Lemma transferFrom_dsl_sat_spec_1:
    forall st env msg this,
      spec_require (funcspec_transferFrom_1 _from _to _value this env msg) st ->
      forall st0 result,
        dsl_exec transferFrom_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_transferFrom_1 _from _to _value this env msg) st (ret_st result) /\
        spec_events (funcspec_transferFrom_1 _from _to _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpaused [Hreq_blncs_lo [Hreq_blncs_hi [Hreq_allwd_lo Hreq_allwd_hi]]]].
    apply Nat.leb_le in Hreq_blncs_lo.
    generalize (nat_nooverflow_dsl_nooverflow _ st env msg Hreq_blncs_hi).
    clear Hreq_blncs_hi. intros Hreq_blncs_hi.
    apply Nat.leb_le in Hreq_allwd_lo.
    apply Nat.ltb_lt in Hreq_allwd_hi.

    simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpaused in Hexec; simpl in Hexec.

    unfold ">="%dsl, dsl_balances_access in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_blncs_lo in Hexec.
    simpl in Hexec.

    rewrite Hreq_blncs_hi in Hexec.
    simpl in Hexec.

    unfold dsl_allowed_access in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_allwd_lo in Hexec.
    simpl in Hexec.

    unfold "<"%dsl in Hexec; simpl in Hexec.
    rewrite (max_uint256_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_allwd_hi in Hexec.
    simpl in Hexec.

    unfold funcspec_transferFrom_1.
    rewrite <- Hexec; clear Hexec.
    unfold "+"%dsl, "-"%dsl.
    repeat rewrite (value_immutable _ _ _).
    repeat rewrite (from_immutable _ _ _).
    repeat rewrite (to_immutable _ _ _).
    repeat (split; simpl; auto).
  Qed.

  Lemma transferFrom_dsl_sat_spec_2:
    forall st env msg this,
      spec_require (funcspec_transferFrom_2 _from _to _value this env msg) st ->
      forall st0 result,
        dsl_exec transferFrom_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_transferFrom_2 _from _to _value this env msg) st (ret_st result) /\
        spec_events (funcspec_transferFrom_2 _from _to _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq. destruct Hreq as [Hpaused [Hreq_blncs_lo [Hreq_blncs_hi [Hreq_allwd_lo Hreq_allwd_hi]]]].
    generalize (nat_nooverflow_dsl_nooverflow _ st env msg Hreq_blncs_hi).
    clear Hreq_blncs_hi. intros Hreq_blncs_hi.
    apply Nat.leb_le in Hreq_blncs_lo.
    apply Nat.leb_le in Hreq_allwd_lo.

    simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpaused in Hexec; simpl in Hexec.

    unfold ">="%dsl, dsl_balances_access in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_blncs_lo in Hexec.
    simpl in Hexec.

    rewrite Hreq_blncs_hi in Hexec.
    simpl in Hexec.

    unfold dsl_allowed_access in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_allwd_lo in Hexec.
    simpl in Hexec.

    unfold "<"%dsl in Hexec; simpl in Hexec.
    rewrite (max_uint256_immutable _ _ _) in Hexec.
    rewrite (from_immutable _ _ _) in Hexec.
    rewrite Hreq_allwd_hi in Hexec.
    rewrite (Nat.ltb_irrefl _) in Hexec.
    simpl in Hexec.

    unfold funcspec_transferFrom_2.
    rewrite <- Hexec.
    unfold "+"%dsl, "-"%dsl.
    repeat rewrite (value_immutable _ _ _).
    repeat rewrite (from_immutable _ _ _).
    repeat rewrite (to_immutable _ _ _).
    repeat (split; auto).
  Qed.

  Lemma transferFrom_cond_dec:
    forall st,
      Decidable.decidable
        (_from = _to \/ _from <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat).
  Proof.
    intros.
    apply Decidable.dec_or.
    - apply Nat.eq_decidable.
    - apply Decidable.dec_and.
      + apply neq_decidable.
      + apply Nat.le_decidable.
  Qed.

  Lemma transferFrom_cond_impl:
    forall st env msg,
      ~ (_from = _to \/ _from <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat) ->
      (((from == to)
        || ((fun (st : state) (env : Model.env) (msg : message) =>
               st_balances st (to st env msg)) <= max_uint256 - value)) st env msg) = ofalse.
  Proof.
    intros st env msg Hneg.

    unfold "=="%dsl, "||"%dsl, "||"%bool, "<="%dsl, "-"%dsl.
    rewrite (from_immutable _ _ _).
    rewrite (to_immutable _ _ _).
    rewrite (value_immutable _ _ _).
    rewrite (max_uint256_immutable _ _ _).

    apply (Decidable.not_or _ _) in Hneg.
    destruct Hneg as [Hneq Hneg].

    apply Nat.eqb_neq in Hneq.
    rewrite Hneq; simpl.

    destruct value_in_range as [_ Hvalue].
    assert (Hvalue': (MAX_UINT256 >= _value)%nat);
      auto.
    rewrite (minus_safe _ _ Hvalue').

    apply (Decidable.not_and _ _ (neq_decidable _ _)) in Hneg.
    destruct Hneg.
    - apply Nat.eqb_neq in Hneq. apply H in Hneq. inversion Hneq.
    - apply not_le in H.
      apply Nat.leb_gt.
      auto.
  Qed.

  (* If no require can be satisfied, transferFrom() must revert to the initial state *)
  Lemma transferFrom_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_transferFrom_1 _from _to _value this env msg) st ->
      ~ spec_require (funcspec_transferFrom_2 _from _to _value this env msg) st ->
      (forall addr0 addr1, (st_allowed st (addr0, addr1) <= MAX_UINT256)%nat) ->
      forall st0 result,
        dsl_exec transferFrom_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    unfold funcspec_transferFrom_1, funcspec_transferFrom_2, ">="%nat.
    intros st env msg this Hreq1_neg Hreq2_neg Hallwd_inv st0 result Hexec;
      simpl in Hreq1_neg, Hreq2_neg.

    assert (Hreq1_impl:
              st_paused st = ofalse ->
              (_value <= st_balances st _from)%nat ->
              (_from = _to \/ _from <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat) ->
              ~(_value <= st_allowed st (_from, m_sender msg) < MAX_UINT256)).
    {
      intros Hpause Hvalue.
      apply Decidable.or_not_l_iff_1.
      - apply transferFrom_cond_dec.
      - generalize Hvalue; clear Hvalue.
        apply Decidable.or_not_l_iff_1.
        + apply Nat.le_decidable.
        + generalize Hpause; clear Hpause.
          apply Decidable.or_not_l_iff_1.
          * apply beq_decidable.
          * { apply Decidable.not_and in Hreq1_neg.
              - destruct Hreq1_neg.
                + left; auto.
                + right.
                  { apply Decidable.not_and in H.
                    - destruct H.
                      + left; auto.
                      + right.
                        { apply Decidable.not_and in H.
                          - destruct H; solve [ left; auto | right; auto ].
                          - apply transferFrom_cond_dec.
                        }
                    - apply Nat.le_decidable.
                  }
              - apply beq_decidable.
            }
    }
    clear Hreq1_neg.

    assert (Hreq2_impl:
              st_paused st = ofalse ->
              (_value <= st_balances st _from)%nat ->
              (_from = _to \/ _from <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat) ->
              ~((_value <= st_allowed st (_from, m_sender msg))%nat /\
                st_allowed st (_from, m_sender msg) = MAX_UINT256)).
    {
      intros Hpause Hvalue.
      apply Decidable.or_not_l_iff_1.
      - apply transferFrom_cond_dec.
      - generalize Hvalue; clear Hvalue.
        apply Decidable.or_not_l_iff_1.
        + apply Nat.le_decidable.
        + generalize Hpause; clear Hpause.
          apply Decidable.or_not_l_iff_1.
          * apply beq_decidable.
          * { apply Decidable.not_and in Hreq2_neg.
              - destruct Hreq2_neg.
                + left; auto.
                + right.
                  { apply Decidable.not_and in H.
                    - destruct H.
                      + left; auto.
                      + right.
                        { apply Decidable.not_and in H.
                          - destruct H; solve [ left; auto | right; auto ].
                          - apply transferFrom_cond_dec.
                        }
                    - apply Nat.le_decidable.
                  }
              - apply beq_decidable.
            }
    }
    clear Hreq2_neg.

    simpl in Hexec.

    destruct (bool_dec (st_paused st) ofalse).
    - (* paused = false *)
      generalize (Hreq1_impl e); clear Hreq1_impl; intros Hreq1_impl.
      generalize (Hreq2_impl e); clear Hreq2_impl; intros Hreq2_impl.

      unfold "!"%dsl in Hexec.
      rewrite e in Hexec; simpl in Hexec.

      { destruct (le_dec _value (st_balances st _from)).
        - (* balances[from] >= value *)
          generalize (Hreq1_impl l); clear Hreq1_impl; intros Hreq1_impl.
          generalize (Hreq2_impl l); clear Hreq2_impl; intros Hreq2_impl.

          apply Nat.leb_le in l.

          simpl in Hexec.
          unfold ">="%dsl, dsl_balances_access in Hexec.
          rewrite (Nat.ltb_antisym _ _) in Hexec.
          rewrite (from_immutable _ _ _) in Hexec.
          rewrite (value_immutable _ _ _) in Hexec.
          rewrite l in Hexec; simpl in Hexec.

          destruct (transferFrom_cond_dec st).
          + (* from = to \/ balances[to] < MAX_UINT256 - value *)
            generalize (Hreq1_impl H); clear Hreq1_impl; intros Hreq1_impl.
            apply (Decidable.not_and _ _ (Nat.le_decidable _ _)) in Hreq1_impl.
            assert (Himpl: (_value <= st_allowed st (_from, m_sender msg))%nat ->
                           ~ (st_allowed st (_from, m_sender msg) < MAX_UINT256)%nat).
            {
              apply Decidable.or_not_l_iff_1.
              - apply Nat.le_decidable.
              - auto.
            }
            clear Hreq1_impl; rename Himpl into Hreq1_impl.

            generalize (Hreq2_impl H); clear Hreq2_impl; intros Hreq2_impl.
            apply (Decidable.not_and _ _ (Nat.le_decidable _ _)) in Hreq2_impl.
            assert(Himpl: (_value <= st_allowed st (_from, m_sender msg))%nat ->
                          st_allowed st (_from, m_sender msg) <> MAX_UINT256).
            {
              apply Decidable.or_not_l_iff_1.
              - apply Nat.le_decidable.
              - auto.
            }
            clear Hreq2_impl; rename Himpl into Hreq2_impl.

            generalize (nat_nooverflow_dsl_nooverflow _ _ env msg H); intros Hcond.
            unfold dsl_allowed_access in Hexec.
            rewrite Hcond in Hexec; simpl in Hexec; clear Hcond.

            rewrite (from_immutable _ _ _) in Hexec.
            rewrite (value_immutable _ _ _) in Hexec.

            destruct (le_dec _value (st_allowed st (_from, m_sender msg))).
            * (* allowed[from][msg.sender] >= value *)
              generalize (Hreq1_impl l0); clear Hreq1_impl; intros Hreq1_impl.
              generalize (Hreq2_impl l0); clear Hreq2_impl; intros Hreq2_impl.

              apply not_lt in Hreq1_impl.
              apply Nat.lt_gt_cases in Hreq2_impl.
              destruct Hreq2_impl.
              {
                unfold ">="%nat in Hreq1_impl. auto.
                apply (Nat.lt_le_trans _ _ _ H0) in Hreq1_impl.
                apply Nat.lt_irrefl in Hreq1_impl.
                inversion Hreq1_impl.
              }
              {
                generalize (Hallwd_inv _from (m_sender msg)).
                intros Hle.
                apply (Nat.le_lt_trans _ _ _ Hle) in H0.
                apply Nat.lt_irrefl in H0.
                inversion H0.
              }

            * (* allowed[from][msg.sender] < value *)
              apply not_le in n.
              apply Nat.ltb_lt in n.
              rewrite n in Hexec; simpl in Hexec.

              rewrite <- Hexec.
              split; auto.

          + (* from <> to /\ balances[to] >= MAX_UINT256 + value *)
            apply (transferFrom_cond_impl st env msg) in H.
            rewrite H in Hexec; simpl in Hexec.

            rewrite <- Hexec.
            split; auto.

        - (* balances[from] < value *)
          apply Nat.leb_nle in n.

          simpl in Hexec.
          unfold ">="%dsl, dsl_balances_access in Hexec.
          rewrite (Nat.ltb_antisym _ _) in Hexec.
          rewrite (from_immutable _ _ _) in Hexec.
          rewrite (value_immutable _ _ _) in Hexec.
          rewrite n in Hexec; simpl in Hexec.

          rewrite <- Hexec.
          split; auto.
      }

    - (* paused = true *)
      apply not_false_is_true in n.
      unfold "!"%dsl in Hexec.
      rewrite n in Hexec; simpl in Hexec.

      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_transfer_from.

Section dsl_transfer.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{to: state -> env -> message -> address}.
  Context `{_to: address}.
  Context `{value: state -> env -> message -> uint256}.
  Context `{_value: uint256}.
  Context `{max_uint256: state -> env -> message -> uint256}.

  (* Arguments are immutable, generated from solidity *)
  Context `{to_immutable: forall st env msg, to st env msg = _to}.
  Context `{value_immutable: forall st env msg, value st env msg = _value}.
  Context `{value_in_range: (_value >= 0 /\ _value <= MAX_UINT256)%nat}.
  Context `{max_uint256_immutable: forall st env msg, max_uint256 st env msg = MAX_UINT256}.

  (* DSL representation of transfer(), generated from solidity *)
  Definition transfer_dsl : Stmt :=
    (@require(!paused) ;
     @require(balances[msg.sender] >= value) ;
     @require((msg.sender == to) || (balances[to] <= max_uint256 - value)) ;
     @balances[msg.sender] -= value ;
     @balances[to] += value ;
     (@emit Transfer(msg.sender, to, value)) ;
     (@return true)
    ).

  (* Auxiliary lemmas *)
  Lemma nat_nooverflow_dsl_nooverflow':
    forall (m: state -> a2v) st env msg,
      (m_sender msg = _to \/ (m_sender msg <> _to /\ (m st _to <= MAX_UINT256 - _value)))%nat ->
      ((msg.sender == to) ||
       ((fun st env msg => m st (to st env msg)) <= max_uint256 - value))%dsl st env msg = otrue.
  Proof.
    intros m st env msg Hnat.

    unfold "||"%dsl, "||"%bool, "=="%dsl, "<="%dsl, "-"%dsl.
    rewrite (to_immutable st env msg),
            (max_uint256_immutable st env msg),
            (value_immutable st env msg).
    destruct Hnat.
    - rewrite H. rewrite (Nat.eqb_refl _). reflexivity.
    - destruct H as [Hneq Hle].
      apply Nat.eqb_neq in Hneq. rewrite Hneq.
      destruct value_in_range as [_ Hvalue].
      assert (Hlo: (MAX_UINT256 >= _value)%nat);
        auto.
      rewrite (minus_safe _ _ Hlo).
      apply Nat.leb_le in Hle. exact Hle.
  Qed.

  (* Manually proved *)
  Lemma transfer_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_transfer _to _value this env msg) st ->
      forall st0 result,
        dsl_exec transfer_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_transfer _to _value this env msg) st (ret_st result) /\
        spec_events (funcspec_transfer _to _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    unfold funcspec_transfer in Hreq; simpl in Hreq.
    destruct Hreq as [Hpaused [Hreq_blncs_lo Hreq_blncs_hi]].
    unfold ">="%nat in Hreq_blncs_lo. apply Nat.leb_le in Hreq_blncs_lo.
    generalize(nat_nooverflow_dsl_nooverflow' _ st env msg Hreq_blncs_hi).
    clear Hreq_blncs_hi. intros Hreq_blncs_hi.

    unfold transfer_dsl in Hexec; simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpaused in Hexec; simpl in Hexec.

    unfold ">="%dsl, dsl_balances_access in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite Hreq_blncs_lo in Hexec; simpl in Hexec.

    rewrite Hreq_blncs_hi in Hexec. simpl in Hexec.

    unfold funcspec_transfer.
    rewrite <- Hexec.
    unfold "+"%dsl, "-"%dsl.
    repeat rewrite (value_immutable _ _ _).
    repeat rewrite (to_immutable _ _ _).
    repeat (split; auto).
  Qed.

  Lemma transfer_cond_impl:
    forall st env msg,
      m_sender msg <> _to /\
      ~ (m_sender msg <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat) ->
      (((fun (_ : state) (_ : Model.env) (msg : message) => m_sender msg) == to)
       || ((fun (st : state) (env : Model.env) (msg : message) =>
              st_balances st (to st env msg)) <= max_uint256 - value)) st env msg = ofalse.
  Proof.
    intros st env msg Hcond.

    unfold "=="%dsl, "||"%dsl, "||"%bool, "<="%dsl, "-"%dsl.
    rewrite (value_immutable _ _ _).
    rewrite (to_immutable _ _ _).
    rewrite (max_uint256_immutable _ _ _).
    destruct value_in_range as [_ Hvalue].
    rewrite (minus_safe _ _ Hvalue).

    destruct Hcond as [Hneq Heq].
    apply Nat.eqb_neq in Hneq; rewrite Hneq; simpl.

    apply (Decidable.not_and _ _ (neq_decidable _ _)) in Heq.
    destruct Heq.

    - apply Nat.eqb_neq in Hneq.
      apply H in Hneq; inversion Hneq.

    - apply not_le in H.
      apply Nat.leb_gt.
      auto.
  Qed.

  (* If no require can be satisfied, transfer() must revert to the initial state *)
  Lemma transfer_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_transfer _to _value this env msg) st ->
      forall st0 result,
        dsl_exec transfer_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.

    simpl in Hreq_neg.

    assert (Hreq_impl:
              st_paused st = ofalse ->
              (_value <= st_balances st (m_sender msg))%nat ->
              ~(m_sender msg = _to \/
                m_sender msg <> _to /\ (st_balances st _to <= MAX_UINT256 - _value)%nat)).
    {
      intros Hpaused.
      apply Decidable.or_not_l_iff_1.
      - apply Nat.le_decidable.
      - generalize Hpaused; clear Hpaused.
        apply Decidable.or_not_l_iff_1.
        + apply beq_decidable.
        + apply Decidable.not_and in Hreq_neg.
          * { destruct Hreq_neg.
              - left; auto.
              - right. apply Decidable.not_and in H.
                + destruct H; solve [ left; auto | right; auto ].
                + apply Nat.le_decidable.
            }
          * apply beq_decidable.
    }
    clear Hreq_neg.

    simpl in Hexec.
    destruct (bool_dec (st_paused st) ofalse).
    - (* paused = false *)
      generalize (Hreq_impl e); clear Hreq_impl; intros Hreq_impl.

      unfold "!"%dsl in Hexec.
      rewrite e in Hexec; simpl in Hexec.

      { destruct (le_dec _value (st_balances st (m_sender msg))).
        - (* balances[msg.sender] >= value *)
          generalize (Hreq_impl l); clear Hreq_impl; intros Hreq.
          apply Decidable.not_or in Hreq.

          apply Nat.leb_le in l.

          simpl in Hexec.
          unfold ">="%dsl, dsl_balances_access in Hexec.
          rewrite (value_immutable _ _ _) in Hexec.
          rewrite (Nat.ltb_antisym _ _) in Hexec.
          rewrite l in Hexec; simpl in Hexec.

          apply (transfer_cond_impl st env msg)in Hreq.
          rewrite Hreq in Hexec; clear Hreq; simpl in Hexec.

          rewrite <- Hexec.
          split; auto.

        - (* balances[msg.sender] < value *)
          apply not_le in n.
          apply Nat.leb_gt in n.

          simpl in Hexec.
          unfold ">="%dsl, dsl_balances_access in Hexec.
          rewrite (value_immutable _ _ _) in Hexec.
          rewrite (Nat.ltb_antisym _ _) in Hexec.
          rewrite n in Hexec; simpl in Hexec.

          rewrite <- Hexec.
          split; auto.
      }

    - (* paused = true *)
      apply not_false_is_true in n.
      unfold "!"%dsl in Hexec.
      rewrite n in Hexec; simpl in Hexec.

      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_transfer.

Section dsl_balanceOf.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{ _owner: state -> env -> message -> address }.
  Context `{ __owner: address }.

  (* Arguments are immutable, generated from solidity *)
  Context `{ owner_immutable: forall st env msg, _owner st env msg = __owner }.

  (* DSL representation of transfer(), generated from solidity *)
  Definition balanceOf_dsl : Stmt :=
    (@return balances[_owner]).

  (* Manually proved *)
  Lemma balanceOf_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_balanceOf __owner this env msg) st ->
      forall st0 result,
        dsl_exec balanceOf_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_balanceOf __owner this env msg) st (ret_st result) /\
        spec_events (funcspec_balanceOf __owner this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hexec.
    unfold funcspec_balanceOf.
    rewrite <- Hexec.
    unfold dsl_balances_access.
    rewrite (owner_immutable _ _ _).
    repeat (split; auto).
  Qed.

  (* If no require can be satisfied, balanceOf() must revert to the initial state *)
  Lemma balanceOf_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_balanceOf __owner this env msg) st ->
      forall st0 result,
        dsl_exec balanceOf_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.
    simpl in Hreq_neg.
    apply (proj1 Decidable.not_true_iff) in Hreq_neg.
    inversion Hreq_neg.
  Qed.

  Close Scope dsl_scope.
End dsl_balanceOf.

Section dsl_approve.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{ spender: state -> env -> message -> address }.
  Context `{ _spender: address }.
  Context `{ value: state -> env -> message -> uint256 }.
  Context `{ _value: uint256 }.

  (* Arguments are immutable, generated from solidity *)
  Context `{ spender_immutable: forall st env msg, spender st env msg = _spender }.
  Context `{ value_immutable: forall st env msg, value st env msg = _value }.

  (* DSL representation of approve(), generated from solidity *)
  Definition approve_dsl : Stmt :=
    (@require(!paused) ;
     @allowed[msg.sender][spender] = value ;
     (@emit Approval(msg.sender, spender, value)) ;
     (@return true)
    ).

  (* Manually proved *)
  Lemma approve_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_approve _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec approve_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_approve _spender _value this env msg) st (ret_st result) /\
        spec_events (funcspec_approve _spender _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    simpl in Hexec.
    unfold "!"%dsl in Hexec; rewrite Hreq in Hexec; simpl in Hexec.
    unfold funcspec_approve.
    rewrite <- Hexec.
    repeat rewrite (spender_immutable _ _ _).
    repeat rewrite (value_immutable _ _ _).
    repeat (split; auto).
  Qed.

  (* If no require can be satisfied, approve() must revert to the initial state *)
  Lemma approve_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_approve _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec approve_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.

    simpl in Hreq_neg.
    apply not_false_is_true in Hreq_neg.

    simpl in Hexec; unfold "!"%dsl in Hexec.
    rewrite Hreq_neg in Hexec; simpl in Hexec.

    rewrite <- Hexec.
    split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_approve.

Section dsl_allowance.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{ _owner: state -> env -> message -> address }.
  Context `{ __owner: address }.
  Context `{ spender: state -> env -> message -> address }.
  Context `{ _spender: address }.

  (* Arguments are immutable, generated from solidity *)
  Context `{ _owner_immutable: forall st env msg, _owner st env msg = __owner }.
  Context `{ spender_immutable: forall st env msg, spender st env msg = _spender }.

  (* DSL representation of transfer(), generated from solidity *)
  Definition allowance_dsl : Stmt :=
    (@return allowed[_owner][spender]).

  (* Manually proved *)
  Lemma allowance_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_allowance __owner _spender this env msg) st ->
      forall st0 result,
        dsl_exec allowance_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_allowance __owner _spender this env msg) st (ret_st result) /\
        spec_events (funcspec_allowance __owner _spender this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hexec.
    unfold funcspec_allowance.
    rewrite <- Hexec.
    unfold dsl_allowed_access.
    rewrite (_owner_immutable _ _ _).
    rewrite (spender_immutable _ _ _).
    repeat (split; auto).
  Qed.

  (* If no require can be satisfied, allowance() must revert to the initial state *)
  Lemma allowance_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_allowance __owner _spender this env msg) st ->
      forall st0 result,
        dsl_exec allowance_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.
    simpl in Hreq_neg.
    apply (proj1 Decidable.not_true_iff) in Hreq_neg.
    inversion Hreq_neg.
  Qed.

  Close Scope dsl_scope.
End dsl_allowance.

Section dsl_constructor.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{ initialAmount : state -> env -> message -> uint256 }.
  Context `{ _initialAmount: uint256 }.
  Context `{ decimalUnits : state -> env -> message -> uint8 }.
  Context `{ _decimalUnits: uint8 }.
  Context `{ tokenName: state -> env -> message -> string }.
  Context `{ _tokenName: string }.
  Context `{ tokenSymbol: state -> env -> message -> string }.
  Context `{ _tokenSymbol: string }.

  (* Arguments are immutable, generated from solidity *)
  Context `{ initialAmount_immutable: forall st env msg, initialAmount st env msg = _initialAmount }.
  Context `{ decimalUnits_immutable: forall st env msg, decimalUnits st env msg = _decimalUnits }.
  Context `{ tokenName_immutable: forall st env msg, tokenName st env msg = _tokenName }.
  Context `{ tokenSymbol_immutable: forall st env msg, tokenSymbol st env msg = _tokenSymbol }.

  (* DSL representation of constructor, generated from solidity *)
  Definition ctor_dsl : Stmt :=
    (@balances[msg.sender] = initialAmount ;
     @totalSupply = initialAmount ;
     @name = tokenName ;
     @decimals = decimalUnits ;
     @symbol = tokenSymbol ;
     @paused = false ;
     @owner = msg.sender ;
     @ctor
    ).

  (* Manually proved *)
  Lemma ctor_dsl_sat_spec:
    forall st,
      st_balances st = $0 ->
      st_allowed st = $0 ->
      forall env msg this,
        spec_require (funcspec_PausableToken _initialAmount _tokenName _decimalUnits _tokenSymbol this env msg) st ->
        forall st0 result,
          dsl_exec ctor_dsl st0 st env msg this nil = result ->
          spec_trans (funcspec_PausableToken _initialAmount _tokenName _decimalUnits _tokenSymbol this env msg) st (ret_st result) /\
          spec_events (funcspec_PausableToken _initialAmount _tokenName _decimalUnits _tokenSymbol this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st Hblns_init Hallwd_init env msg this Hreq st0 result Hexec.

    simpl in Hexec.
    unfold funcspec_PausableToken.
    rewrite <- Hexec.
    repeat rewrite (initialAmount_immutable _ _ _).
    repeat rewrite (decimalUnits_immutable _ _ _).
    repeat rewrite (tokenName_immutable _ _ _).
    repeat rewrite (tokenSymbol_immutable _ _ _).
    rewrite Hblns_init.
    rewrite Hallwd_init.
    repeat (split; auto).
  Qed.

  Close Scope dsl_scope.
End dsl_constructor.

Section dsl_pause.
  Open Scope dsl_scope.

  (* DSL representation of constructor, generated from solidity *)
  Definition pause_dsl : Stmt :=
    (@require(owner == msg.sender) ;
     @require(!paused) ;
     @paused = true ;
     (@emit Pause( ))
    ).

  (* Manually proved *)
  Lemma pause_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_pause this env msg) st ->
      forall st0 result,
        dsl_exec pause_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_pause this env msg) st (ret_st result) /\
        spec_events (funcspec_pause this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpause Howner].

    simpl in Hexec.
    unfold "=="%dsl in Hexec.
    rewrite Howner in Hexec; rewrite (Nat.eqb_refl _) in Hexec; simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpause in Hexec; simpl in Hexec.

    simpl.
    rewrite <- Hexec.
    repeat (split; auto).
  Qed.

  (* If no require can be satisfied, pause() must revert to the initial state *)
  Lemma pause_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_pause this env msg) st ->
      forall st0 result,
        dsl_exec pause_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.

    simpl in Hreq_neg.
    assert (Hreq_impl: st_paused st = ofalse -> ~ st_owner st = m_sender msg).
    {
      apply Decidable.or_not_l_iff_1.
      - apply beq_decidable.
      - apply (Decidable.not_and _ _ (beq_decidable _ _)) in Hreq_neg.
        auto.
    }
    clear Hreq_neg.

    simpl in Hexec. unfold "=="%dsl, "!"%dsl in Hexec.
    destruct (Nat.eq_dec (st_owner st) (m_sender msg)).
    - (* owner == msg.sender *)
      apply Nat.eqb_eq in e.
      rewrite e in Hexec; simpl in Hexec.

      destruct (bool_dec (st_paused st) ofalse).
      + (* paused = false *)
        apply Hreq_impl in e0.
        apply Nat.eqb_eq in e.
        apply e0 in e; inversion e.

      + (* paused = true *)
        apply not_false_is_true in n.
        rewrite n in Hexec; simpl in Hexec.
        rewrite <- Hexec.
        split; auto.

    - (* owner != msg.sender *)
      apply Nat.eqb_neq in n.
      rewrite n in Hexec; simpl in Hexec.
      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_pause.

Section dsl_unpause.
  Open Scope dsl_scope.

  (* DSL representation of constructor, generated from solidity *)
  Definition unpause_dsl : Stmt :=
    (@require(owner == msg.sender) ;
     @require(paused) ;
     @paused = false ;
     (@emit Unpause( ))
    ).

  (* Manually proved *)
  Lemma unpause_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_unpause this env msg) st ->
      forall st0 result,
        dsl_exec unpause_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_unpause this env msg) st (ret_st result) /\
        spec_events (funcspec_unpause this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpause Howner].

    simpl in Hexec.
    unfold "=="%dsl in Hexec.
    rewrite Howner in Hexec; rewrite (Nat.eqb_refl _) in Hexec; simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpause in Hexec; simpl in Hexec.

    rewrite <- Hexec.
    repeat (split; simpl; auto).
  Qed.

  (* If no require can be satisfied, unpause() must revert to the initial state *)
  Lemma unpause_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_unpause this env msg) st ->
      forall st0 result,
        dsl_exec unpause_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.

    simpl in Hreq_neg.
    assert (Hreq_impl: st_paused st = otrue -> ~ st_owner st = m_sender msg).
    {
      apply Decidable.or_not_l_iff_1.
      - apply beq_decidable.
      - apply (Decidable.not_and _ _ (beq_decidable _ _)) in Hreq_neg.
        auto.
    }
    clear Hreq_neg.

    simpl in Hexec. unfold "=="%dsl, "!"%dsl in Hexec.
    destruct (Nat.eq_dec (st_owner st) (m_sender msg)).
    - (* owner == msg.sender *)
      apply Nat.eqb_eq in e.
      rewrite e in Hexec; simpl in Hexec.

      destruct (bool_dec (st_paused st) otrue).
      + (* paused = true *)
        apply Hreq_impl in e0.
        apply Nat.eqb_eq in e.
        apply e0 in e; inversion e.

      + (* paused = false *)
        apply not_true_is_false in n.
        rewrite n in Hexec; simpl in Hexec.
        rewrite <- Hexec.
        split; auto.

    - (* owner != msg.sender *)
      apply Nat.eqb_neq in n.
      rewrite n in Hexec; simpl in Hexec.
      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_unpause.

Section dsl_increaseApproval.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{spender: state -> env -> message -> address}.
  Context `{_spender: address}.
  Context `{value: state -> env -> message -> uint256}.
  Context `{_value: uint256}.
  Context `{max_uint256: state -> env -> message -> uint256}.

  (* Arguments are immutable, generated from solidity *)
  Context `{spender_immutable: forall st env msg, spender st env msg = _spender}.
  Context `{value_immutable: forall st env msg, value st env msg = _value}.
  Context `{value_in_range: (0 <= _value /\ _value <= MAX_UINT256)%nat}.
  Context `{max_uint256_immutable: forall st env msg, max_uint256 st env msg = MAX_UINT256}.

  (* DSL representation of constructor, generated from solidity *)
  Definition increaseApproval_dsl : Stmt :=
    (@require(!paused) ;
     @require(allowed[msg.sender][spender] <= max_uint256 - value) ;
     @allowed[msg.sender][spender] += value ;
     (@emit Approval(msg.sender, spender, allowed[msg.sender][spender])) ;
     (@return true)
    ).

  Lemma increaseApproval_dsl_sat_spec:
    forall st env msg this,
      spec_require (funcspec_increaseApproval _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec increaseApproval_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_increaseApproval _spender _value this env msg) st (ret_st result) /\
        spec_events (funcspec_increaseApproval _spender _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpaused Hallowed].
    apply Nat.leb_le in Hallowed.

    simpl in Hexec.
    unfold "!"%dsl in Hexec; rewrite Hpaused in Hexec; simpl in Hexec.

    unfold "<="%dsl, "-"%dsl, dsl_allowed_access in Hexec.
    rewrite (spender_immutable _ _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (max_uint256_immutable _ _ _) in Hexec.
    destruct value_in_range as [_ Hvalue].
    rewrite (minus_safe _ _ Hvalue) in Hexec.
    rewrite Hallowed in Hexec; simpl in Hexec.

    rewrite <- Hexec.
    unfold "+"%dsl, "-"%dsl.
    repeat rewrite (spender_immutable _ _ _).
    repeat rewrite (value_immutable _ _ _).
    repeat (split; simpl; auto).
  Qed.

  (* If no require can be satisfied, increaseApproval() must revert to the initial state *)
  Lemma increaseApproval_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_increaseApproval _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec increaseApproval_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_neg st0 result Hexec.

    simpl in Hreq_neg.
    assert (Hreq_impl: st_paused st = ofalse ->
                       ~ (st_allowed st (m_sender msg, _spender) <= MAX_UINT256 - _value)%nat).
    {
      apply Decidable.or_not_l_iff_1.
      - apply beq_decidable.
      - apply (Decidable.not_and _ _ (beq_decidable _ _)) in Hreq_neg. auto.
    }
    clear Hreq_neg.

    destruct (bool_dec (st_paused st) ofalse).
    - (* paused == false *)
      generalize (Hreq_impl e); clear Hreq_impl; intros Hreq_impl.
      apply Nat.leb_nle in Hreq_impl.

      simpl in Hexec.
      unfold "!"%dsl in Hexec.
      rewrite e in Hexec; simpl in Hexec.

      unfold "<="%dsl, "-"%dsl, dsl_allowed_access in Hexec.
      rewrite (spender_immutable _ _ _) in Hexec.
      rewrite (value_immutable _ _ _) in Hexec.
      rewrite (max_uint256_immutable _ _ _) in Hexec.
      destruct value_in_range as [_ Hvalue].
      rewrite (minus_safe _ _ Hvalue) in Hexec.
      rewrite Hreq_impl in Hexec; simpl in Hexec.

      rewrite <- Hexec.
      split; auto.

    - (* paused == true *)
      apply not_false_is_true in n.

      simpl in Hexec.
      unfold "!"%dsl in Hexec.
      rewrite n in Hexec; simpl in Hexec.

      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_increaseApproval.

Section dsl_decreaseApproval.
  Open Scope dsl_scope.

  (* Declare arguments, generated from solidity *)
  Context `{spender: state -> env -> message -> address}.
  Context `{_spender: address}.
  Context `{value: state -> env -> message -> uint256}.
  Context `{_value: uint256}.
  Context `{max_uint256: state -> env -> message -> uint256}.

  (* Arguments are immutable, generated from solidity *)
  Context `{spender_immutable: forall st env msg, spender st env msg = _spender}.
  Context `{value_immutable: forall st env msg, value st env msg = _value}.
  Context `{value_in_range: (0 <= _value /\ _value <= MAX_UINT256)%nat}.
  Context `{max_uint256_immutable: forall st env msg, max_uint256 st env msg = MAX_UINT256}.

  (* DSL representation of constructor, generated from solidity *)
  Definition decreaseApproval_dsl : Stmt :=
    (@require(!paused) ;
     @uint256 oldValue = allowed[msg.sender][spender] ;
     @if (oldValue < value) {
         (@allowed[msg.sender][spender] = 0)
     } else {
         (@allowed[msg.sender][spender] -= value)
     } ;
     (@emit Approval(msg.sender, spender, allowed[msg.sender][spender])) ;
     (@return true)
    ).

  Lemma decreaseApproval_dsl_sat_spec_1:
    forall st env msg this,
      spec_require (funcspec_decreaseApproval_1 _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec decreaseApproval_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_decreaseApproval_1 _spender _value this env msg) st (ret_st result) /\
        spec_events (funcspec_decreaseApproval_1 _spender _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpaused Hallowed].
    apply Nat.ltb_lt in Hallowed.

    simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpaused in Hexec; simpl in Hexec.

    unfold dsl_allowed_access, "<"%dsl in Hexec.
    rewrite (spender_immutable _ _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite Hallowed in Hexec; simpl in Hexec.

    rewrite <- Hexec.
    repeat rewrite (spender_immutable _ _ _).
    repeat (split; simpl; auto).
    rewrite <- (tmap_get_upd_eq (st_allowed st) (m_sender msg, _spender) 0%nat) at 2.
    reflexivity.
  Qed.

  Lemma decreaseApproval_dsl_sat_spec_2:
    forall st env msg this,
      spec_require (funcspec_decreaseApproval_2 _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec decreaseApproval_dsl st0 st env msg this nil = result ->
        spec_trans (funcspec_decreaseApproval_2 _spender _value this env msg) st (ret_st result) /\
        spec_events (funcspec_decreaseApproval_2 _spender _value this env msg) (ret_st result) (ret_evts result).
  Proof.
    intros st env msg this Hreq st0 result Hexec.

    simpl in Hreq.
    destruct Hreq as [Hpaused Hallowed].
    apply Nat.leb_le in Hallowed.

    simpl in Hexec.
    unfold "!"%dsl in Hexec.
    rewrite Hpaused in Hexec; simpl in Hexec.

    unfold dsl_allowed_access, "<"%dsl in Hexec.
    rewrite (spender_immutable _ _ _) in Hexec.
    rewrite (value_immutable _ _ _) in Hexec.
    rewrite (Nat.ltb_antisym _ _) in Hexec.
    rewrite Hallowed in Hexec; simpl in Hexec.

    rewrite <- Hexec.
    unfold "-"%dsl.
    repeat rewrite (spender_immutable _ _ _).
    repeat rewrite (value_immutable _ _ _).
    repeat (split; simpl; auto).
  Qed.

  (* If no require can be satisfied, decreaseApproval() must revert to the initial state *)
  Lemma decreaseApproval_dsl_revert:
    forall st env msg this,
      ~ spec_require (funcspec_decreaseApproval_1 _spender _value this env msg) st ->
      ~ spec_require (funcspec_decreaseApproval_2 _spender _value this env msg) st ->
      forall st0 result,
        dsl_exec decreaseApproval_dsl st0 st env msg this nil = result ->
        result = Stop st0 (ev_revert this :: nil).
  Proof.
    intros st env msg this Hreq_1 Hreq_2 st0 result Hexec.

    simpl in Hreq_1.
    assert (Hreq1_impl: st_paused st = ofalse ->
                        ~ (st_allowed st (m_sender msg, _spender) < _value)%nat).
    {
      apply Decidable.or_not_l_iff_1.
      - apply beq_decidable.
      - apply (Decidable.not_and _ _ (beq_decidable _ _)) in Hreq_1; auto.
    }
    clear Hreq_1.

    simpl in Hreq_2.
    assert (Hreq2_impl: st_paused st = ofalse ->
                        ~(st_allowed st (m_sender msg, _spender) >= _value)%nat).
    {
      apply Decidable.or_not_l_iff_1.
      - apply beq_decidable.
      - apply (Decidable.not_and _ _ (beq_decidable _ _)) in Hreq_2; auto.
    }
    clear Hreq_2.

    destruct (bool_dec (st_paused st) ofalse).

    - (* paused == false *)
      generalize (Hreq1_impl e); clear Hreq1_impl; intros Hreq1_impl.
      generalize (Hreq2_impl e); clear Hreq2_impl; intros Hreq2_impl.

      apply Nat.nlt_ge in Hreq1_impl.
      apply Hreq2_impl in Hreq1_impl.
      inversion Hreq1_impl.

    - (* paused == true *)
      apply not_false_is_true in n.

      simpl in Hexec.
      unfold "!"%dsl in Hexec.
      rewrite n in Hexec; simpl in Hexec.

      rewrite <- Hexec.
      split; auto.
  Qed.

  Close Scope dsl_scope.
End dsl_decreaseApproval.