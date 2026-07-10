fn arguments {
  any_args()
  any_args(value, other)
  any_args(value, label=other)
  any_args(label~)
  any_args(label?=other)
  any_args(label?)

  exp_args()
  exp_args(value, other + 1)
  exp_args(value, label=other)
  exp_args(label~)

  id_args()
  id_args(value, other)
  id_args(value, 1)
  id_args(label=value)

  const_args()
  const_args(1, "two")
  const_args(1, value)
  const_args(label=1)
}
