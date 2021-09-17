(* PG'OCaml is a set of OCaml bindings for the PostgreSQL database.
 *
 * PG'OCaml - type safe interface to PostgreSQL.
 * Copyright (C) 2005-2009 Richard Jones and other authors.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this library; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *)

(**	Type-safe access to PostgreSQL databases. *)

open CalendarLib

module type THREAD = sig
  type 'a t
  val return : 'a -> 'a t
  val (>>=) : 'a t -> ('a -> 'b t) -> 'b t
  val fail : exn -> 'a t
  val catch : (unit -> 'a t) -> (exn -> 'a t) -> 'a t

  type in_channel
  type out_channel
  val open_connection : Unix.sockaddr -> (in_channel * out_channel) t
  val output_char : out_channel -> char -> unit t
  val output_binary_int : out_channel -> int -> unit t
  val output_string : out_channel -> string -> unit t
  val flush : out_channel -> unit t
  val input_char : in_channel -> char t
  val input_binary_int : in_channel -> int t
  val really_input : in_channel -> Bytes.t -> int -> int -> unit t
  val close_in : in_channel -> unit t
end

module type PGOCAML_GENERIC =
sig

type 'a t				(** Database handle. *)

type 'a monad

type isolation = [ `Serializable | `Repeatable_read | `Read_committed | `Read_uncommitted ]

type access = [ `Read_write | `Read_only ]

exception Error of string
(** For library errors. *)

exception PostgreSQL_Error of string * (char * string) list
(** For errors generated by the PostgreSQL database back-end.  The
    first argument is a printable error message.  The second argument
    is the complete set of error fields returned from the back-end.

    See
    [http://www.postgresql.org/docs/8.1/static/protocol-error-fields.html] *)

(** {6 Connection management} *)

type connection_desc = {
  user: string;
  port: int;
  password: string;
  host: [ `Hostname of string | `Unix_domain_socket_dir of string];
  database: string
}

val describe_connection : ?host:string -> ?port:int -> ?user:string -> ?password:string -> ?database:string -> ?unix_domain_socket_dir:string -> unit -> connection_desc
(** Produce the actual, concrete connection parameters based on the values and
  * availability of the various configuration variables.
  *)

val connection_desc_to_string : connection_desc -> string
(** Produce a human-readable textual representation of a concrete connection
  * descriptor (the password is NOT included in the output of this function)
  * for logging and error reporting purposes.
  *)

val connect : ?host:string -> ?port:int -> ?user:string -> ?password:string -> ?database:string -> ?unix_domain_socket_dir:string -> ?desc:connection_desc -> unit -> 'a t monad
(** Connect to the database.

    The normal [$PGDATABASE], etc. environment variables are available. *)

val close : 'a t -> unit monad
(** Close the database handle.

    You must call this after you have finished with the handle, or else
    you will get leaked file descriptors. *)

val ping : 'a t -> unit monad
(** Ping the database.

    If the database is not available, some sort of exception will be
    thrown. *)

val alive : 'a t -> bool monad
(** This function is a wrapper of [ping] that returns a boolean
    instead of raising an exception. *)

(** {6 Transactions} *)

val begin_work : ?isolation:isolation -> ?access:access -> ?deferrable:bool -> 'a t -> unit monad
(** Start a transaction. *)

val commit : 'a t -> unit monad
(** Perform a COMMIT operation on the database. *)

val rollback : 'a t -> unit monad
(** Perform a ROLLBACK operation on the database. *)

val transact :
  'a t ->
  ?isolation:isolation ->
  ?access:access ->
  ?deferrable:bool ->
  ('a t -> 'b monad) ->
  'b monad
(** [transact db ?isolation ?access ?deferrable f] wraps your function
    [f] inside a transactional block.  First it calls [begin_work] with
    [isolation], [access] and [deferrable], then calls [f] and do
    [rollback] if [f] raises an exception, [commit] otherwise. *)

(** {6 Serial column} *)

val serial : 'a t -> string -> int64 monad
(** This is a shorthand for [SELECT CURRVAL(serial)].

    For a table called [table] with serial column [id] you would typically
    call this as [serial dbh "table_id_seq"] after the previous INSERT
    operation to get the serial number of the inserted row. *)

val serial4 : 'a t -> string -> int32 monad
(** As {!serial} but assumes that the column is a SERIAL or SERIAL4
    type. *)

val serial8 : 'a t -> string -> int64 monad
(** Same as {!serial}. *)

(** {6 Miscellaneous} *)

val max_message_length : int ref
(** Maximum message length accepted from the back-end.

    The default is [Sys.max_string_length], which means that we will try
    to read as much data from the back-end as we can, and this may
    cause us to run out of memory (particularly on 64 bit machines),
    causing a possible denial of service.

    You may want to set this to a smaller size to avoid this happening. *)

val verbose : int ref
(** Verbosity.

    0 means don't print anything.
    1 means print short error messages as returned from the back-end.
    2 means print all messages as returned from the back-end.

    Messages are printed on [stderr].
    Default verbosity level is 1. *)

val set_private_data : 'a t -> 'a -> unit
(** Attach some private data to the database handle.

    NB. The pa_pgsql camlp4 extension uses this for its own purposes,
    which means that in most programs you will not be able to attach
    private data to the database handle. *)

val private_data : 'a t -> 'a
(** Retrieve some private data previously attached to the database
    handle. If no data has been attached, raises [Not_found].

    NB. The pa_pgsql camlp4 extension uses this for its own purposes,
    which means that in most programs you will not be able to attach
    private data to the database handle.
*)

val uuid : 'a t -> string
(** Retrieve the unique identifier for this connection. *)

type pa_pg_data = (string, bool) Hashtbl.t
(** When using pa_pgsql, database handles have type
    [PGOCaml.pa_pg_data PGOCaml.t] *)

(** {6 Low level query interface - DO NOT USE DIRECTLY} *)

type oid = int32 [@@deriving show]

type param = string option (* None is NULL. *)
type result = string option (* None is NULL. *)
type row = result list (* One row is a list of fields. *)

val prepare : 'a t -> query:string -> ?name:string -> ?types:oid list -> unit -> unit monad
(** [prepare conn ~query ?name ?types ()] prepares the statement
    [query] and optionally names it [name] and sets the parameter types
    to [types].

    If no name is given, then the "unnamed" statement is overwritten.
    If no types are given, then the PostgreSQL engine infers types.
    Synchronously checks for errors. *)

val execute_rev : 'a t -> ?name:string -> ?portal:string -> params:param list -> unit -> row list monad
val execute : 'a t -> ?name:string -> ?portal:string -> params:param list -> unit -> row list monad
(** [execute conn ?name ~params ()] executes the named or unnamed
    statement [name], with the given parameters [params], returning the
    result rows (if any).

    There are several steps involved at the protocol layer:

    (1) a "portal" is created from the statement, binding the
    parameters in the statement (Bind).

    (2) the portal is executed (Execute).

    (3) we synchronise the connection (Sync).

    The optional [?portal] parameter may be used to name the portal
    created in step (1) above (otherwise the unnamed portal is used).
    This is only important if you want to call {!describe_portal} to
    find out the result types. *)

val cursor : 'a t -> ?name:string -> ?portal:string -> params:param list -> (row -> unit monad) -> unit monad

val close_statement : 'a t -> ?name:string -> unit -> unit monad
(** [close_statement conn ?name ()] closes a prepared statement and
    frees up any resources. *)

val close_portal : 'a t -> ?portal:string -> unit -> unit monad
(** [close_portal conn ?portal ()] closes a portal and frees up any
    resources. *)

val inject : 'a t -> ?name:string -> string -> row list monad
(** [inject conn ?name query] executes the statement [query] and
    optionally names it [name] and gives the result. *)

val alter : 'a t -> ?name:string -> string -> unit monad
(** [alter conn ?name query] executes the statement [query] and
    optionally names it [name]. Same as inject but ignoring the
    result. *)

type result_description = {
  name : string;			(** Field name. *)
  table : oid option;			(** OID of table. *)
  column : int option;			(** Column number of field in table. *)
  field_type : oid;			(** The type of the field. *)
  length : int;				(** Length of the field. *)
  modifier : int32;			(** Type modifier. *)
}[@@deriving show]
type row_description = result_description list [@@deriving show]

type params_description = param_description list
and param_description = {
  param_type : oid;			(** The type of the parameter. *)
}

val describe_statement : 'a t -> ?name:string -> unit -> (params_description * row_description option) monad
(** [describe_statement conn ?name ()] describes the named or unnamed
    statement's parameter types and result types. *)

val describe_portal : 'a t -> ?portal:string -> unit -> row_description option monad
(** [describe_portal conn ?portal ()] describes the named or unnamed
    portal's result types. *)

(** {6 Low level type conversion functions - DO NOT USE DIRECTLY} *)

val name_of_type : oid -> string
(** Returns the OCaml equivalent type name to the PostgreSQL type
    [oid].

    For instance, [name_of_type (Int32.of_int 23)] returns ["int32"]
    because the OID for PostgreSQL's internal [int4] type is [23].

    As another example, [name_of_type (Int32.of_int 25)] returns
    ["string"]. *)

type inet = Unix.inet_addr * int
type timestamptz = Calendar.t * Time_Zone.t
type int16 = int
type bytea = string (* XXX *)
type point = float * float
type hstore = (string * string option) list
type numeric = string
type uuid = string
type jsonb = string

type bool_array = bool option list
type int16_array = int16 option list
type int32_array = int32 option list
type int64_array = int64 option list
type string_array = string option list
type float_array = float option list
type timestamp_array = Calendar.t option list
type uuid_array = string option list

(** The following conversion functions are used by pa_pgsql to convert
    values in and out of the database. *)

val string_of_oid : oid -> string
val string_of_bool : bool -> string
val string_of_int : int -> string
val string_of_int16 : int16 -> string
val string_of_int32 : int32 -> string
val string_of_int64 : int64 -> string
val string_of_float : float -> string
val string_of_point : point -> string
val string_of_hstore : hstore -> string
val string_of_numeric : numeric -> string
val string_of_uuid : uuid -> string
val string_of_jsonb : jsonb -> string
val string_of_inet : inet -> string
val string_of_timestamp : Calendar.t -> string
val string_of_timestamptz : timestamptz -> string
val string_of_date : Date.t -> string
val string_of_time : Time.t -> string
val string_of_interval : Calendar.Period.t -> string
val string_of_bytea : bytea -> string
val string_of_string : string -> string
val string_of_unit : unit -> string

val string_of_bool_array : bool_array -> string
val string_of_int16_array : int16_array -> string
val string_of_int32_array : int32_array -> string
val string_of_int64_array : int64_array -> string
val string_of_string_array : string_array -> string
val string_of_bytea_array : string_array -> string
val string_of_float_array : float_array -> string
val string_of_timestamp_array : timestamp_array -> string
val string_of_arbitrary_array : ('a -> string) -> 'a option list -> string
val string_of_uuid_array : uuid_array -> string

val comment_src_loc : unit -> bool

val find_custom_typconvs
  :  ?typnam:string
  -> ?lookin:string
  -> ?colnam:string
  -> ?argnam:string
  -> unit
  -> ((string * string) option, string) Rresult.result

val oid_of_string : string -> oid
val bool_of_string : string -> bool
val int_of_string : string -> int
val int16_of_string : string -> int16
val int32_of_string : string -> int32
val int64_of_string : string -> int64
val float_of_string : string -> float
val point_of_string : string -> point
val hstore_of_string : string -> hstore
val numeric_of_string : string -> numeric
val uuid_of_string : string -> uuid
val jsonb_of_string : string -> jsonb
val inet_of_string : string -> inet
val timestamp_of_string : string -> Calendar.t
val timestamptz_of_string : string -> timestamptz
val date_of_string : string -> Date.t
val time_of_string : string -> Time.t
val interval_of_string : string -> Calendar.Period.t
val bytea_of_string : string -> bytea
val unit_of_string : string -> unit

val bool_array_of_string : string -> bool_array
val int16_array_of_string : string -> int16_array
val int32_array_of_string : string -> int32_array
val int64_array_of_string : string -> int64_array
val string_array_of_string : string -> string_array
val float_array_of_string : string -> float_array
val timestamp_array_of_string : string -> timestamp_array
val arbitrary_array_of_string : (string -> 'a) -> string -> 'a option list

val bind : 'a monad -> ('a -> 'b monad) -> 'b monad
val return : 'a -> 'a monad

end


module Make : functor (Thread : THREAD) ->
  PGOCAML_GENERIC with type 'a monad = 'a Thread.t
