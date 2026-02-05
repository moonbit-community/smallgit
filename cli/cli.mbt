///|
async fn sgt_add(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_cat_file(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_check_ignore(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_checkout(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_commit(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_hash_object(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_init(argv : ArrayView[String]) -> Unit raise {
  let path = match argv {
    [] => "."
    [path] => path
    other => fail("init: invalid argv \{other}")
  }
  @smallgit.Repository::new(path).init()
}

///|
async fn sgt_ls_files(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_ls_tree(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_rev_parse(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_rm(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_show_ref(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_status(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
async fn sgt_tag(argv : ArrayView[String]) -> Unit raise {
  ...
}

///|
let command_table : Map[String, async (ArrayView[String]) -> Unit] = {
  "add": sgt_add,
  "cat-file": sgt_cat_file,
  "check-ignore": sgt_check_ignore,
  "checkout": sgt_checkout,
  "commit": sgt_commit,
  "hash-object": sgt_hash_object,
  "init": sgt_init,
  "ls-files": sgt_ls_files,
  "ls-tree": sgt_ls_tree,
  "rev-parse": sgt_rev_parse,
  "rm": sgt_rm,
  "show-ref": sgt_show_ref,
  "status": sgt_status,
  "tag": sgt_tag,
}

///|
async fn main {
  let argv = @sys.get_cli_args()
  guard argv is [_, .. argv]
  if argv.is_empty() {
    // print help
  } else {
    try {
      match command_table.get(argv[0]) {
        Some(command) => command(argv[1:])
        None => fail("command \{argv[0]} not implemented")
      }
    } catch {
      err => {
        println("error: \{err}")
        panic()
      }
    }
  }
}
