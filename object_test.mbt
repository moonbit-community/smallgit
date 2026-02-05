///|
fn assert_bytes_eq(
  left : Bytes,
  right : Bytes,
  context~ : String,
) -> Unit raise {
  let left_len = left.length()
  let right_len = right.length()
  if left_len != right_len {
    fail("\{context}: length \{left_len} != \{right_len}")
  }
  for i in 0..<left_len {
    if left[i] != right[i] {
      fail("\{context}: byte mismatch at \{i}")
    }
  }
}

///|
fn assert_string_array_eq(
  left : Array[String],
  right : Array[String],
  context~ : String,
) -> Unit raise {
  let left_len = left.length()
  let right_len = right.length()
  if left_len != right_len {
    fail("\{context}: length \{left_len} != \{right_len}")
  }
  for i in 0..<left_len {
    if left[i] != right[i] {
      fail("\{context}: value mismatch at \{i}")
    }
  }
}

///|
fn assert_header_array_eq(
  left : Array[(String, String)],
  right : Array[(String, String)],
  context~ : String,
) -> Unit raise {
  let left_len = left.length()
  let right_len = right.length()
  if left_len != right_len {
    fail("\{context}: length \{left_len} != \{right_len}")
  }
  for i in 0..<left_len {
    let (left_key, left_value) = left[i]
    let (right_key, right_value) = right[i]
    if left_key != right_key || left_value != right_value {
      fail("\{context}: header mismatch at \{i}")
    }
  }
}

///|
test "object round-trip blob" {
  let payload : Bytes = [0x00, 0x01, 0x02, 0x7f, 0x80, 0xff]
  let blob = @smallgit.BlobObject::deserialize(payload)
  let round_trip = blob.serialize()
  assert_bytes_eq(round_trip, payload, context="blob round-trip")
}

///|
test "object round-trip tree" {
  let oid1 : Bytes = [
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
    0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13,
  ]
  let oid2 : Bytes = [
    0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33,
    0x22, 0x11, 0x00, 0x10, 0x20, 0x30, 0x40,
  ]
  let buf = @buffer.new()
  buf.write_string_utf8("100644".to_string_view())
  buf.write_byte(b' ')
  buf.write_string_utf8("README.md".to_string_view())
  buf.write_byte(0)
  buf.write_bytes(oid1)
  buf.write_string_utf8("40000".to_string_view())
  buf.write_byte(b' ')
  buf.write_string_utf8("src lib".to_string_view())
  buf.write_byte(0)
  buf.write_bytes(oid2)
  let encoded = buf.to_bytes()
  let tree = @smallgit.TreeObject::deserialize(encoded)
  let entries = tree.entries
  if entries.length() != 2 {
    fail("tree entries length mismatch")
  }
  let first = entries[0]
  if first.mode != "100644" {
    fail("tree entry 0 mode mismatch")
  }
  if first.name != "README.md" {
    fail("tree entry 0 name mismatch")
  }
  assert_bytes_eq(first.oid, oid1, context="tree entry 0 oid")
  let second = entries[1]
  if second.mode != "40000" {
    fail("tree entry 1 mode mismatch")
  }
  if second.name != "src lib" {
    fail("tree entry 1 name mismatch")
  }
  assert_bytes_eq(second.oid, oid2, context="tree entry 1 oid")
  let round_trip = tree.serialize()
  assert_bytes_eq(round_trip, encoded, context="tree round-trip")
}

///|
test "object round-trip tag" {
  let encoded_text : String =
    #|object 0123456789abcdef0123456789abcdef01234567
    #|type commit
    #|tag v1.2.3
    #|tagger Alice Example <alice@example.com> 1700000000 +0000
    #|x-custom yes
    #|encoding utf-8
    #|
    #|release notes
    #|line two
    #|
  let encoded = @utf8.encode(encoded_text)
  let tag = @smallgit.TagObject::deserialize(encoded)
  if tag.object != "0123456789abcdef0123456789abcdef01234567" {
    fail("tag object mismatch")
  }
  if tag.object_type != "commit" {
    fail("tag type mismatch")
  }
  if tag.tag != "v1.2.3" {
    fail("tag name mismatch")
  }
  if tag.tagger != "Alice Example <alice@example.com> 1700000000 +0000" {
    fail("tagger mismatch")
  }
  if tag.message != "release notes\nline two\n" {
    fail("tag message mismatch")
  }
  let extra_headers : Array[(String, String)] = [
    ("x-custom", "yes"),
    ("encoding", "utf-8"),
  ]
  assert_header_array_eq(
    tag.extra_headers,
    extra_headers,
    context="tag extra headers",
  )
  let round_trip = tag.serialize()
  assert_bytes_eq(round_trip, encoded, context="tag round-trip")
}

///|
test "object round-trip commit" {
  let encoded_text : String =
    #|tree aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    #|parent bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    #|parent cccccccccccccccccccccccccccccccccccccccc
    #|author Bob Example <bob@example.com> 1700000001 +0000
    #|committer Bob Example <bob@example.com> 1700000002 +0000
    #|gpgsig dummy-signature
    #|x-reviewer carol@example.com
    #|
    #|implement feature
    #|
    #|details here
    #|
  let encoded = @utf8.encode(encoded_text)
  let commit = @smallgit.CommitObject::deserialize(encoded)
  if commit.tree != "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
    fail("commit tree mismatch")
  }
  let parents : Array[String] = [
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "cccccccccccccccccccccccccccccccccccccccc",
  ]
  assert_string_array_eq(commit.parents, parents, context="commit parents")
  if commit.author != "Bob Example <bob@example.com> 1700000001 +0000" {
    fail("commit author mismatch")
  }
  if commit.committer != "Bob Example <bob@example.com> 1700000002 +0000" {
    fail("commit committer mismatch")
  }
  if commit.message != "implement feature\n\ndetails here\n" {
    fail("commit message mismatch")
  }
  let extra_headers : Array[(String, String)] = [
    ("gpgsig", "dummy-signature"),
    ("x-reviewer", "carol@example.com"),
  ]
  assert_header_array_eq(
    commit.extra_headers,
    extra_headers,
    context="commit extra headers",
  )
  let round_trip = commit.serialize()
  assert_bytes_eq(round_trip, encoded, context="commit round-trip")
}
