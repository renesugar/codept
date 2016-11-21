
module Simple =
struct
  module Core = struct
    type t = Name.t list
    type npath = t
    let compare (x:t) (y:t) = compare x y
    let pp = Pp.(list ~sep:(s".") ) Name.pp
  end
  include Core
  module Set = struct
    include Set.Make(Core)
    let pp ppf s = Pp.(clist Core.pp) ppf (elements s)
  end
  module Map = struct
    include (Map.Make(Core))
    let find_opt k m = try Some(find k m) with Not_found -> None
    let union' s = union (fun _key _m1 m2 -> Some m2) s
  end
  type set = Set.t
  type 'a map = 'a Map.t
  let prefix = List.hd

  let extension a =
    let ext = Filename.extension a in
    String.sub ext 1 (String.length ext - 1)

  let may_change_extension f a =
    match extension a with
    | "" -> a
    | ext ->
      let base = Filename.chop_extension a in
      base ^ f ext

  let rec change_file_extension f = function
    | [] -> []
    | [a] -> [may_change_extension f a ]
    | a :: q -> a :: change_file_extension f q

  let rec chop_extension l = match l with
    | [] -> []
    | [a] -> [Filename.chop_extension a]
    | a :: q -> a :: chop_extension q

  let parse_filename =
    String.split_on_char (String.get (Filename.dir_sep) 0)

end
module S = Simple

module Expr = struct
  type t =
    | T
    | A of Name.t
    | S of t * Name.t
    | F of {f:t; x:t}

  exception Functor_not_expected
  let concrete p: Simple.t =
    let rec concretize l = function
      | T -> l
      | A a -> a :: l
      | F _ -> raise Functor_not_expected
      | S(p,s) -> concretize (s::l) p in
    concretize [] p

  let concrete_with_f p: Simple.t =
    let rec concretize l = function
      | T -> l
      | A a -> a :: l
      | F {f;_} -> concretize l f
      | S(p,s) -> concretize (s::l) p in
    concretize [] p


  let multiples p : Simple.t list =
    let rec concretize stack l = function
      | T -> l :: stack
      | A a -> (a :: l) :: stack
      | F {f;x} -> concretize (concretize stack [] x) l f
      | S(p,s) -> concretize stack (s::l) p in
    concretize [] [] p

  let rev_concrete p = List.rev @@ concrete p

  let from_list l =
    let rec rebuild =
      function
      | [] -> T
      | [a] -> A a
      | a :: q -> S(rebuild q, a)
    in rebuild @@ List.rev l

  let rec pp ppf =
    let p fmt = Format.fprintf ppf fmt in
    function
    | T -> p "T"
    | A name -> p"%s" name
    | S(h,n) -> p "%a.%s" pp h n
    | F {f;x} -> p "%a(%a)" pp f pp x

  let rec prefix = function
    | S(p,_) -> prefix p
    | A n -> n
    | F {f;_} -> prefix f
    | T -> raise @@ Invalid_argument "Paths.Expr: prefix of empty path"
end
module E = Expr

module Pkg = struct
  type source = Local | Unknown | Pkg of Simple.t

  let sep = Filename.dir_sep

  type t = { source: source ; file: Simple.t }
  type path = t

  let filename ?(sep=sep) p =
    begin match p.source with
      | Pkg n -> String.concat sep n ^ sep
      | _ -> ""
    end
    ^
    String.concat sep p.file

  let is_known = function
    | {source=Unknown; _ } -> false
    | _ -> true

  let rec last = function
    | [a] -> a
    | [] -> raise  @@  Invalid_argument "last expected a non-empty-file"
    | _ :: q -> last q


  let extension name =
    let n = String.length name in
    try
      let r = String.rindex name '.' in
      Some (String.sub name (r+1) (n-r-1))
    with Not_found -> None

  let may_chop_extension a =
    try Filename.chop_extension a with
      Invalid_argument _ -> a

  let may_change_extension f a =
    match extension a with
    | None -> a
    | Some ext ->
      let base = Filename.chop_extension a in
      base ^ f ext

  let module_name {file; _ } =
    String.capitalize_ascii @@ may_chop_extension @@ last @@ file

  let update_extension f p =
    { p with file = Simple.change_file_extension f p.file }

  let change_extension ext =
    update_extension ( fun _ -> ext )

  let cmo = change_extension ".cmo"
  let o = change_extension ".o"
  let cmi = change_extension ".cmi"
  let cmx = change_extension ".cmx"

  let mk_dep all native = update_extension @@ function
    | "mli" -> ".cmi"
    | "ml" when all -> ".cmi"
    | "ml" ->
      if native then ".cmx" else ".cmo"
    | s -> raise @@Invalid_argument ("Unknown extension " ^ s)

  let pp_source ppf = function
    | Local -> Pp.fp ppf "Local"
    | Unknown ->  Pp.fp ppf "Unknown"
    | Pkg n -> Pp.fp ppf "Pkg [%a]" Pp.(list ~sep:(const sep) string) n

  let pp_simple ppf {source;file}=
    Pp.fp ppf "(%a)%a" pp_source source
      Pp.(list ~sep:(const sep) string) file

  let pp_gen sep ppf {source;file} =
    begin match source with
      | Local -> ()
      | Unknown -> Pp.fp ppf "?"
      | Pkg s ->
        Pp.fp ppf "%a%s"
          Pp.(list ~sep:(const sep) string) s
          sep
    end;
    Pp.fp ppf "%a"
      Pp.(list ~sep:(const sep) string) file

  let pp = pp_gen sep
  let es ppf = Pp.fp ppf {|"%s"|}

  let reflect_source ppf =
    function
    | Local -> Pp.fp ppf "Local"
    | Unknown ->  Pp.fp ppf "Unknown"
    | Pkg n -> Pp.fp ppf "Pkg [%a]" Pp.(list ~sep:(s "; ") es) n

  let reflect ppf {source;file} =
    Pp.fp ppf "{source=%a; file=[%a]}"
      reflect_source source
      Pp.(list ~sep:(const "; ") es) file

  module Set = struct
    include Set.Make(struct type t = path let compare = compare end)
    let pp ppf s = Pp.(clist pp) ppf (elements s)
  end

  type set = Set.t

  let slash = String.get sep 0

  let local file = { source = Local; file }

end
module P = Pkg