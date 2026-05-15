namespace Smoke

inductive Result where
  | ok
  deriving Repr, BEq

structure Info where
  message : String
  deriving Repr, BEq

end Smoke
