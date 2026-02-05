///|
pub struct Repository {
  worktree : String
  git_dir : String
  config : String
}

///|
pub async fn Repository::new(worktree : String, force~ : Bool = false) -> Repository {
  let pathbuf = @path.PathBuilder::from_path(@path.Path::parse(worktree))
  let git_dir = {
    pathbuf.add_directory(".git")
    pathbuf.to_path().to_string()
  }
  if !(force || @fs.exists(git_dir)) {
    fail("\{git_dir} not exist")
  }
  let config_path = {
    pathbuf.set_file(base="config", extension="")
    pathbuf.to_path()
  }
  let config = @fs.read_file(config_path.to_string()).text()
  Repository::{ worktree, git_dir, config }
}

///|
pub async fn Repository::init(self : Repository) -> Unit {
  // implement `git init`

  // Create .git directory if it doesn't exist
  if !@fs.exists(self.git_dir) {
    @fs.mkdir(self.git_dir, permission=0o755)
  }

  // Create refs directory and subdirectories
  let refs_dir = self.git_dir + "/refs"
  @fs.mkdir(refs_dir, permission=0o755)
  let refs_heads_dir = refs_dir + "/heads"
  @fs.mkdir(refs_heads_dir, permission=0o755)
  let refs_tags_dir = refs_dir + "/tags"
  @fs.mkdir(refs_tags_dir, permission=0o755)

  // Create objects directory
  let objects_dir = self.git_dir + "/objects"
  @fs.mkdir(objects_dir, permission=0o755)

  // Create hooks directory
  let hooks_dir = self.git_dir + "/hooks"
  @fs.mkdir(hooks_dir, permission=0o755)

  // Create HEAD file pointing to refs/heads/main
  let head_file = self.git_dir + "/HEAD"
  let head_content = "ref: refs/heads/main\n"
  @fs.write_file(head_file, head_content)

  // Create config file with basic configuration
  let config_file = self.git_dir + "/config"
  let config_content =
    #|[core]
    #|	repositoryformatversion = 0
    #|	filemode = true
    #|	bare = false
    #|	logallrefupdates = true
    #|
  @fs.write_file(config_file, config_content)

  // Create description file
  let description_file = self.git_dir + "/description"
  let description_content = "Unnamed repository; edit this file 'description' to name the repository.\n"
  @fs.write_file(description_file, description_content)
}
