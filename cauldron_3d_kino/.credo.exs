%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{included: ["lib/"], excluded: []},
      checks: %{
        extra: [
          {Credo.Check.Design.AliasUsage, [if_nested_deeper_than: 2, if_called_more_often_than: 0]}
        ]
      }
    }
  ]
}
