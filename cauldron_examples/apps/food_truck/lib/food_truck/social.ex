defmodule FoodTruck.Social do
  @moduledoc """
  What people post about the truck: everyone's posts (`posts/1`), the highlighted ones
  Social Feed+ subscribers see (`highlighted/1`), and the trending topics
  (`trending/0`). A post names its author's favourite donut and carries tags, each a
  title, a donut or a city.
  """

  alias FoodTruck.Donut

  @type tag :: {:title, String.t()} | {:donut, Donut.id()} | {:city, atom()}
  @type post :: %{
          id: String.t(),
          favorite: Donut.id(),
          message: String.t(),
          posted_at: NaiveDateTime.t(),
          tags: [tag()]
        }

  @classic 0
  @blueberry_frosted 1
  @cosmos 3
  @strawberry_sprinkles 4
  @lemon_chocolate 5
  @rainbow 6
  @picnic_basket 7
  @figure_skater 8
  @powdered_chocolate 9
  @powdered_strawberry 10
  @custard 11
  @fire_zest 13
  @black_raspberry 14
  @daytime 15
  @nighttime 16

  @standard [
    {@classic, "I can't wait for the Food Truck to make its way to London!",
     [{:city, :london}, {:title, "I'm waiting..."}, {:title, "One of these days!"}]},
    {@black_raspberry,
     "I'm really looking forward to trying the new chocolate donuts next time the truck is in town.",
     [
       {:donut, @lemon_chocolate},
       {:title, "Chocolate!!!"},
       {:donut, @powdered_chocolate},
       {:city, :san_francisco}
     ]},
    {@daytime, "Do you think there are any donuts in space?",
     [{:donut, @cosmos}, {:title, "Space"}]},
    {@nighttime,
     "Thinking of checking out the Food Truck in its new location in SF today, anyone else down?",
     [{:city, :san_francisco}, {:title, "Donuts for one"}, {:title, "Unless...?"}]},
    {@custard, "I heard the Food Truck was in Cupertino today! Did anyone get a chance to visit?",
     [{:city, :cupertino}, {:title, "Food Truck sighting"}]},
    {@figure_skater,
     "Okay, long day of work complete. Time to grab a bunch of donuts and get out of here!",
     [
       {:donut, @figure_skater},
       {:donut, @blueberry_frosted},
       {:donut, @powdered_strawberry},
       {:title, "Many more"}
     ]},
    {@blueberry_frosted,
     "I think I just saw the Food Truck on its way to San Francisco! Taxi, follow that truck!",
     [{:donut, @classic}, {:city, :san_francisco}, {:title, "And away we go!"}]}
  ]

  @highlighted [
    {@picnic_basket,
     "I'm going to place a huge order next time the Food Truck is in San Francisco!!",
     [{:city, :san_francisco}, {:donut, @classic}, {:title, "Like two dozen!"}]},
    {@rainbow,
     "Just told my coworkers about the Food Truck and we are currently a group of 20 heading out.",
     [
       {:title, "How many donuts are too many"},
       {:title, "Trick question"},
       {:title, "Please don't tell me"}
     ]},
    {@fire_zest,
     "Once the Food Truck adds carrot-flavored donuts; I'm going to order a million of them!",
     [
       {:title, "Carrot"},
       {:title, "Carrots of Social Feed"},
       {:title, "Bunnies of Social Feed"},
       {:title, "Carrots"},
       {:title, "Donuts for Bunnies"}
     ]}
  ]

  @trending [
    {:donut, @powdered_chocolate},
    {:donut, @blueberry_frosted},
    {:title, "Warmed Up"},
    {:title, "Room Temperature"},
    {:city, :san_francisco},
    {:donut, @rainbow},
    {:title, "Rainbow Sprinkles"},
    {:donut, @strawberry_sprinkles},
    {:title, "Dairy Free"},
    {:city, :cupertino},
    {:city, :london},
    {:title, "Gluten Free"},
    {:donut, @fire_zest},
    {:donut, @black_raspberry},
    {:title, "Carrots"},
    {:title, "Donut vs Doughnut"}
  ]

  @doc "Everyone's posts, newest first, the newest a few minutes before `now`."
  @spec posts(NaiveDateTime.t()) :: [post()]
  def posts(now), do: dated(@standard, "post", now, 11)

  @doc "The highlighted posts for Social Feed+ subscribers, newest first."
  @spec highlighted(NaiveDateTime.t()) :: [post()]
  def highlighted(now), do: dated(@highlighted, "highlight", now, 23)

  @doc "The trending topics the Truck screen shows."
  @spec trending() :: [tag()]
  def trending, do: @trending

  defp dated(posts, prefix, now, seed) do
    random = :rand.seed_s(:exsss, {seed, seed, seed})

    posts
    |> Enum.with_index()
    |> Enum.map_reduce({now, random}, fn {{favorite, message, tags}, index}, {time, random} ->
      {minutes, random} = :rand.uniform_s(26, random)
      time = NaiveDateTime.add(time, -(minutes + 4) * 60)

      post = %{
        id: "#{prefix}#{index}",
        favorite: favorite,
        message: message,
        posted_at: NaiveDateTime.truncate(time, :second),
        tags: tags
      }

      {post, {time, random}}
    end)
    |> elem(0)
  end
end
