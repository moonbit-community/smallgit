///|
pub struct Repository {
  worktree : String
  git_dir : String
  config : String
}

///|
pub async fn Repository::new(worktree : String) -> Repository {
  let pathbuf = @path.PathBuilder::from_path(@path.Path::parse(worktree))
  let git_dir = {
    pathbuf.add_directory(".git")
    pathbuf.to_path().to_string()
  }
  if !@fs.exists(git_dir) {
    fail("\{git_dir} not exist")
  }
  let config_path = {
    pathbuf.set_file(base="config", extension="")
    pathbuf.to_path()
  }
  let config = @fs.read_file(config_path.to_string()).text()
  Repository::{ worktree, git_dir, config }
}
