use std assert

#[test]
def test_addition [] {
    assert equal (1 + 2) 3
}

#[test]
#[ignore]
def test_skip [] {
    # this won't be run
}
