
/// Git Object
pub trait Object {
  deserialize(Bytes) -> Self
  serialize(Self) -> Bytes
}

pub struct BlobObject(Bytes)

pub impl Object for BlobObject with serialize(self) {
  self.0
}

pub impl Object for BlobObject with deserialize(self) {
  BlobObject(self)
}

struct TreeObject {

}

struct TagObject {

}

struct CommitObject {

}