defmodule Megablast.Stages do
  @moduledoc """
  The five stages of the lane, as data: each its name, its walls, its backdrop and rock,
  the waves that come and how far up the lane they come, the guardian half way, and the
  boss at the end.

  A wave is `{at, kind, formation, count, where}`: `at` tiles up the stage, a
  `Megablast.Foe` kind, a formation (`:line`, `:vee`, `:column`, `:arc` or `:scatter`),
  how many, and where across the lane (`:left`, `:middle`, `:right`, or a number of tiles
  from the middle). A stage's `length` is how far up the lane its boss waits.
  """

  @stages [
    %{
      number: 1,
      name: "THE CHITIN LANE",
      backdrop: :deep_1,
      rock: :rock_1,
      walls: [rock: :rock_1, wall_least: 2, wall_most: 6, wall_period: 16, turret_every: 13],
      length: 420,
      waves: [
        {30, :drone, :line, 5, :middle},
        {60, :drone, :vee, 5, :left},
        {85, :drone, :vee, 5, :right},
        {110, :dart, :column, 3, :middle},
        {140, :drone, :arc, 6, :middle},
        {165, :spore, :line, 3, :middle},
        {195, :dart, :scatter, 4, :middle},
        {255, :drone, :line, 6, :left},
        {275, :orb, :line, 2, :middle},
        {305, :drone, :vee, 7, :middle},
        {330, :spore, :scatter, 4, :middle},
        {355, :dart, :column, 4, :left},
        {370, :dart, :column, 4, :right},
        {390, :orb, :line, 3, :middle}
      ],
      guardian: {220, :guardian, 40},
      boss: :hive_mother
    },
    %{
      number: 2,
      name: "THE WEEPING FLUE",
      backdrop: :deep_2,
      rock: :rock_2,
      walls: [rock: :rock_2, wall_least: 3, wall_most: 7, wall_period: 12, turret_every: 10],
      length: 460,
      waves: [
        {25, :drone, :arc, 6, :middle},
        {50, :dart, :scatter, 5, :middle},
        {80, :orb, :line, 2, :left},
        {95, :orb, :line, 2, :right},
        {125, :spore, :vee, 5, :middle},
        {150, :drone, :column, 6, :left},
        {165, :drone, :column, 6, :right},
        {190, :shell, :line, 1, :middle},
        {270, :dart, :vee, 6, :middle},
        {300, :orb, :arc, 4, :middle},
        {330, :spore, :scatter, 6, :middle},
        {360, :shell, :line, 2, :middle},
        {395, :dart, :scatter, 6, :middle},
        {425, :drone, :vee, 9, :middle}
      ],
      guardian: {235, :guardian, 60},
      boss: :leviathan
    },
    %{
      number: 3,
      name: "THE SPORE GARDENS",
      backdrop: :deep_3,
      rock: :rock_3,
      walls: [rock: :rock_3, wall_least: 2, wall_most: 8, wall_period: 10, turret_every: 9],
      length: 500,
      waves: [
        {25, :spore, :line, 4, :middle},
        {50, :spore, :vee, 5, :left},
        {70, :spore, :vee, 5, :right},
        {100, :orb, :arc, 4, :middle},
        {130, :dart, :scatter, 6, :middle},
        {160, :shell, :line, 2, :middle},
        {190, :drone, :arc, 8, :middle},
        {215, :spore, :scatter, 7, :middle},
        {290, :orb, :line, 3, :left},
        {305, :orb, :line, 3, :right},
        {340, :shell, :vee, 3, :middle},
        {375, :spore, :column, 6, :middle},
        {410, :dart, :vee, 7, :middle},
        {445, :orb, :arc, 5, :middle},
        {470, :spore, :scatter, 8, :middle}
      ],
      guardian: {250, :guardian, 80},
      boss: :spore_engine
    },
    %{
      number: 4,
      name: "THE IRON VEINS",
      backdrop: :deep_4,
      rock: :rock_4,
      walls: [rock: :rock_4, wall_least: 3, wall_most: 8, wall_period: 9, turret_every: 7],
      length: 540,
      waves: [
        {25, :dart, :scatter, 6, :middle},
        {55, :shell, :line, 2, :middle},
        {85, :orb, :arc, 5, :middle},
        {115, :drone, :vee, 9, :middle},
        {145, :shell, :vee, 3, :middle},
        {175, :dart, :column, 5, :left},
        {190, :dart, :column, 5, :right},
        {220, :spore, :scatter, 6, :middle},
        {245, :orb, :line, 4, :middle},
        {330, :shell, :line, 3, :middle},
        {360, :dart, :scatter, 8, :middle},
        {395, :orb, :arc, 6, :middle},
        {430, :shell, :vee, 4, :middle},
        {470, :drone, :arc, 10, :middle},
        {500, :dart, :scatter, 9, :middle}
      ],
      guardian: {275, :guardian, 100},
      boss: :iron_warden
    },
    %{
      number: 5,
      name: "THE QUEEN'S HEART",
      backdrop: :deep_5,
      rock: :rock_5,
      walls: [rock: :rock_5, wall_least: 2, wall_most: 9, wall_period: 8, turret_every: 6],
      length: 580,
      waves: [
        {25, :orb, :arc, 5, :middle},
        {55, :shell, :vee, 3, :middle},
        {85, :dart, :scatter, 9, :middle},
        {115, :spore, :scatter, 8, :middle},
        {145, :orb, :line, 4, :left},
        {160, :orb, :line, 4, :right},
        {195, :shell, :line, 4, :middle},
        {225, :drone, :vee, 11, :middle},
        {255, :dart, :column, 6, :middle},
        {350, :orb, :arc, 7, :middle},
        {385, :shell, :vee, 5, :middle},
        {420, :spore, :scatter, 10, :middle},
        {455, :dart, :scatter, 10, :middle},
        {490, :orb, :arc, 8, :middle},
        {530, :shell, :line, 5, :middle}
      ],
      guardian: {295, :guardian, 130},
      boss: :queen
    }
  ]

  @designs %{
    guardian: %{
      name: "GUARDIAN",
      core: %{art: :guardian, hp: 40, radius: 1.6},
      parts: [],
      sway: 4.0,
      phases: [
        %{below: 1.0, guns: [%{from: :core, every: 1.3, pattern: {:aimed, 3, 0.5}}]},
        %{below: 0.5, guns: [%{from: :core, every: 1.0, pattern: {:ring, 10}}]}
      ]
    },
    hive_mother: %{
      name: "THE HIVE MOTHER",
      core: %{art: :hive_mother, hp: 70, radius: 2.2},
      parts: [
        %{name: :left_sac, art: :hive_sac, hp: 22, radius: 1.0, at: {-3.4, 0.6}},
        %{name: :right_sac, art: :hive_sac, hp: 22, radius: 1.0, at: {3.4, 0.6}}
      ],
      sway: 3.0,
      phases: [
        %{
          below: 1.0,
          guns: [
            %{from: :left_sac, every: 1.5, pattern: {:aimed, 3, 0.45}},
            %{from: :right_sac, every: 1.5, pattern: {:aimed, 3, 0.45}}
          ]
        },
        %{
          below: 0.99,
          guns: [
            %{from: :core, every: 1.2, pattern: {:ring, 12}},
            %{from: :core, every: 0.9, pattern: {:aimed, 1, 0.0}}
          ]
        },
        %{
          below: 0.4,
          guns: [
            %{from: :core, every: 0.8, pattern: {:ring, 14}},
            %{from: :core, every: 0.6, pattern: {:aimed, 3, 0.3}}
          ]
        }
      ]
    },
    leviathan: %{
      name: "THE LEVIATHAN",
      core: %{art: :leviathan, hp: 90, radius: 2.4},
      parts: [
        %{name: :left_eye, art: :leviathan_eye, hp: 28, radius: 0.9, at: {-2.4, -1.2}},
        %{name: :right_eye, art: :leviathan_eye, hp: 28, radius: 0.9, at: {2.4, -1.2}}
      ],
      sway: 4.5,
      phases: [
        %{
          below: 1.0,
          guns: [
            %{from: :left_eye, every: 1.1, pattern: {:aimed, 1, 0.0}},
            %{from: :right_eye, every: 1.1, pattern: {:aimed, 1, 0.0}},
            %{from: :core, every: 2.6, pattern: {:fan, 7, 1.4}}
          ]
        },
        %{
          below: 0.99,
          guns: [
            %{from: :core, every: 1.2, pattern: {:fan, 9, 1.8}},
            %{from: :core, every: 0.7, pattern: {:aimed, 2, 0.2}}
          ]
        },
        %{
          below: 0.35,
          guns: [
            %{from: :core, every: 0.7, pattern: {:fan, 11, 2.2}},
            %{from: :core, every: 1.4, pattern: {:ring, 16}}
          ]
        }
      ]
    },
    spore_engine: %{
      name: "THE SPORE ENGINE",
      core: %{art: :spore_engine, hp: 110, radius: 2.4},
      parts: [
        %{name: :left_vent, art: :spore_vent, hp: 26, radius: 0.9, at: {-3.6, 0.4}},
        %{name: :middle_vent, art: :spore_vent, hp: 26, radius: 0.9, at: {0.0, 2.2}},
        %{name: :right_vent, art: :spore_vent, hp: 26, radius: 0.9, at: {3.6, 0.4}}
      ],
      sway: 2.5,
      phases: [
        %{
          below: 1.0,
          guns: [
            %{from: :left_vent, every: 1.4, pattern: {:rain, 3}},
            %{from: :middle_vent, every: 1.0, pattern: {:aimed, 3, 0.6}},
            %{from: :right_vent, every: 1.4, pattern: {:rain, 3}}
          ]
        },
        %{
          below: 0.99,
          guns: [
            %{from: :core, every: 0.9, pattern: {:ring, 14}},
            %{from: :core, every: 1.6, pattern: {:rain, 7}}
          ]
        },
        %{
          below: 0.4,
          guns: [
            %{from: :core, every: 0.6, pattern: {:ring, 16}},
            %{from: :core, every: 0.8, pattern: {:aimed, 5, 0.8}}
          ]
        }
      ]
    },
    iron_warden: %{
      name: "THE IRON WARDEN",
      core: %{art: :iron_warden, hp: 130, radius: 2.5},
      parts: [
        %{name: :gun_1, art: :warden_gun, hp: 24, radius: 0.8, at: {-4.0, -0.5}},
        %{name: :gun_2, art: :warden_gun, hp: 24, radius: 0.8, at: {-1.8, 1.8}},
        %{name: :gun_3, art: :warden_gun, hp: 24, radius: 0.8, at: {1.8, 1.8}},
        %{name: :gun_4, art: :warden_gun, hp: 24, radius: 0.8, at: {4.0, -0.5}}
      ],
      sway: 3.5,
      phases: [
        %{
          below: 1.0,
          guns:
            for(
              n <- 1..4,
              do: %{from: :"gun_#{n}", every: 1.0 + n * 0.15, pattern: {:aimed, 1, 0.0}}
            )
        },
        %{
          below: 0.99,
          guns: [
            %{from: :core, every: 0.8, pattern: {:fan, 9, 2.0}},
            %{from: :core, every: 1.0, pattern: {:ring, 12}}
          ]
        },
        %{
          below: 0.35,
          guns: [
            %{from: :core, every: 0.5, pattern: {:aimed, 5, 0.9}},
            %{from: :core, every: 0.9, pattern: {:ring, 18}}
          ]
        }
      ]
    },
    queen: %{
      name: "THE QUEEN",
      core: %{art: :queen, hp: 170, radius: 2.8},
      parts: [
        %{name: :left_claw, art: :queen_claw, hp: 34, radius: 1.1, at: {-4.2, 1.2}},
        %{name: :right_claw, art: :queen_claw, hp: 34, radius: 1.1, at: {4.2, 1.2}},
        %{name: :left_eye, art: :leviathan_eye, hp: 22, radius: 0.8, at: {-1.6, -1.8}},
        %{name: :right_eye, art: :leviathan_eye, hp: 22, radius: 0.8, at: {1.6, -1.8}}
      ],
      sway: 5.0,
      phases: [
        %{
          below: 1.0,
          guns: [
            %{from: :left_claw, every: 1.2, pattern: {:fan, 5, 1.0}},
            %{from: :right_claw, every: 1.2, pattern: {:fan, 5, 1.0}},
            %{from: :left_eye, every: 0.9, pattern: {:aimed, 1, 0.0}},
            %{from: :right_eye, every: 0.9, pattern: {:aimed, 1, 0.0}}
          ]
        },
        %{
          below: 0.99,
          guns: [
            %{from: :core, every: 0.6, pattern: {:ring, 16}},
            %{from: :core, every: 0.7, pattern: {:aimed, 3, 0.4}}
          ]
        },
        %{
          below: 0.5,
          guns: [
            %{from: :core, every: 0.45, pattern: {:ring, 18}},
            %{from: :core, every: 0.6, pattern: {:fan, 11, 2.4}}
          ]
        },
        %{
          below: 0.2,
          guns: [
            %{from: :core, every: 0.35, pattern: {:ring, 20}},
            %{from: :core, every: 0.5, pattern: {:aimed, 5, 0.7}}
          ]
        }
      ]
    }
  }

  @doc "How many stages there are."
  @spec count() :: pos_integer()
  def count, do: length(@stages)

  @doc "Stage `number`, from `1`."
  @spec stage(pos_integer()) :: map()
  def stage(number), do: Enum.at(@stages, number - 1)

  @doc "The boss design under `name`, the guardian's health set to `hp` when given."
  @spec design(atom(), pos_integer() | nil) :: map()
  def design(name, hp \\ nil)
  def design(name, nil), do: Map.fetch!(@designs, name)
  def design(name, hp), do: put_in(design(name, nil), [:core, :hp], hp)

  @doc "Where the foes of a wave start, across the lane between `{left, right}` at row `y`."
  @spec places({atom(), atom(), pos_integer(), term()}, {number(), number()}, number()) :: [
          {float(), float()}
        ]
  def places({_kind, formation, count, where}, {left, right}, y) do
    middle = centre(where, {left, right})

    for index <- 0..(count - 1) do
      offset = index - (count - 1) / 2
      {x, back} = slot(formation, offset, index, count)
      {(middle + x) |> max(left + 1.0) |> min(right - 1.0), y - back}
    end
  end

  defp centre(:left, {left, right}), do: left + (right - left) * 0.28
  defp centre(:right, {left, right}), do: left + (right - left) * 0.72
  defp centre(:middle, {left, right}), do: (left + right) / 2
  defp centre(offset, {left, right}) when is_number(offset), do: (left + right) / 2 + offset

  defp slot(:line, offset, _index, _count), do: {offset * 2.0, 0.0}
  defp slot(:vee, offset, _index, _count), do: {offset * 1.8, abs(offset) * 1.4}
  defp slot(:column, _offset, index, _count), do: {0.0, index * 2.2}
  defp slot(:arc, offset, _index, count), do: {offset * 1.9, (1.0 - abs(offset) / count) * 2.4}

  defp slot(:scatter, offset, index, _count),
    do: {offset * 2.3 + :math.sin(index * 2.1) * 1.2, rem(index * 7, 5) * 1.1}
end
