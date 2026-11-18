defmodule Catalog.Screens do
  @moduledoc "The catalog's screens, one for each kind of control."

  import CauldronNative.UI

  @screens [
    text: {"Text and icons", :edit},
    buttons: {"Buttons and menus", :check_circle},
    inputs: {"Text input", :mail},
    selection: {"Selection", :settings},
    dates: {"Dates and times", :calendar},
    progress: {"Progress", :refresh},
    lists: {"Lists", :list},
    layout: {"Layout", :build},
    presentation: {"Sheets and alerts", :info},
    images: {"Images", :star},
    media: {"Media and device", :play},
    places: {"Location and maps", :location},
    notifications: {"Notifications", :notifications},
    charts: {"Charts", :star},
    fold: {"Folding", :phone},
    custom: {"A view of the app's own", :face}
  ]

  @video "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

  @places [
    {:eiffel, "Eiffel Tower", {48.8584, 2.2945}},
    {:louvre, "Louvre", {48.8606, 2.3376}},
    {:notre_dame, "Notre-Dame", {48.8530, 2.3499}},
    {:arc, "Arc de Triomphe", {48.8738, 2.2950}}
  ]

  @fonts [
    :large_title,
    :title,
    :title2,
    :title3,
    :headline,
    :body,
    :callout,
    :subheadline,
    :footnote,
    :caption
  ]
  @icons [
    :home,
    :search,
    :favorite,
    :share,
    :settings,
    :person,
    :cart,
    :mail,
    :phone,
    :location,
    :lock,
    :notifications
  ]

  @doc "The screen named `name` for `state`."
  @spec page(atom(), map()) :: CauldronNative.UI.Node.t()
  def page(:home, state) do
    screen("Catalog", [
      list([
        section(
          "Components",
          for(
            {key, {title, icon}} <- @screens,
            do: button(title, id: key, icon: icon, on_tap: {:open, key})
          )
        ),
        section("Last event", [text(state.last, modifiers: [foreground: :secondary])])
      ]),
      toolbar([button("Settings", icon: :settings, on_tap: {:show, :settings})]),
      sheet([settings(state)],
        shown: state.settings,
        title: "Settings",
        on_dismiss: {:hide, :settings}
      )
    ])
  end

  def page(:text, _state) do
    screen("Text and icons", [
      list([
        section(
          "Text styles",
          for(font <- @fonts, do: text("#{font}", id: font, modifiers: [font: font]))
        ),
        section("Colours", [
          text("Primary", modifiers: [foreground: :primary]),
          text("Secondary", modifiers: [foreground: :secondary]),
          text("Accent", modifiers: [foreground: :accent]),
          text("Destructive", modifiers: [foreground: :destructive]),
          text("Bold", modifiers: [bold: true]),
          text("Custom #3A8F5C", modifiers: [foreground: "#3A8F5C"])
        ]),
        section("Icons", [hstack(for(name <- @icons, do: icon(name, id: name)), spacing: 12)]),
        section("Labels", [
          label("Home", icon: :home),
          label("Favourites", icon: :favorite),
          label("Settings", icon: :settings)
        ]),
        section("Links", [link("Elixir's website", "https://elixir-lang.org")])
      ])
    ])
  end

  def page(:buttons, state) do
    screen("Buttons and menus", [
      list([
        section("Styles", [
          button("Plain", style: :plain, on_tap: {:pressed, "plain"}),
          button("Bordered", style: :bordered, on_tap: {:pressed, "bordered"}),
          button("Prominent", style: :prominent, on_tap: {:pressed, "prominent"}),
          button("Destructive", role: :destructive, on_tap: {:pressed, "destructive"}),
          button("With an icon", icon: :send, on_tap: {:pressed, "icon"}),
          button("Disabled", disabled: true, on_tap: {:pressed, "disabled"})
        ]),
        section("Chips", [
          hstack(
            for({key, title} <- [coffee: "Coffee", tea: "Tea", juice: "Juice"]) do
              chip(title,
                id: key,
                selected: MapSet.member?(state.chips, key),
                on_tap: {:chip, key}
              )
            end
          )
        ]),
        section("Menus", [
          menu("Sort by", [
            button("Name", on_tap: {:pressed, "sort by name"}),
            button("Date", on_tap: {:pressed, "sort by date"}),
            button("Delete all", role: :destructive, on_tap: {:pressed, "delete all"})
          ])
        ]),
        section("Last pressed", [text(state.last)])
      ])
    ])
  end

  def page(:inputs, state) do
    screen("Text input", [
      form([
        section(
          "Fields",
          [
            text_field("Name", value: state.name, on_change: {:set, :name}, capitalize: :words),
            text_field("Email",
              value: state.email,
              on_change: {:set, :email},
              keyboard: :email,
              capitalize: :none,
              autocorrect: false
            ),
            secure_field("Password", value: state.password, on_change: {:set, :password}),
            text_field("Send with return", on_submit: :submit)
          ],
          footer: submitted(state.submitted)
        ),
        section("Many lines", [
          text_editor("Notes", value: state.notes, on_change: {:set, :notes})
        ])
      ])
    ])
  end

  def page(:selection, state) do
    screen("Selection", [
      form([
        section("Switches and sliders", [
          toggle("Wi-Fi", value: state.wifi, on_change: {:set, :wifi}),
          text("Volume #{round(state.volume * 100)}%"),
          slider(value: state.volume, on_change: {:set, :volume}),
          stepper("Guests", value: state.guests, min: 1, max: 10, on_change: {:set, :guests})
        ]),
        section("Pickers", [
          picker("Size", [s: "Small", m: "Medium", l: "Large"],
            value: state.size,
            style: :segmented,
            on_change: {:set, :size}
          ),
          picker(
            "Flavour",
            [vanilla: "Vanilla", chocolate: "Chocolate", strawberry: "Strawberry"],
            value: state.flavour,
            on_change: {:set, :flavour}
          )
        ]),
        section("Inline", [
          picker("Getting there", [bike: "Bike", bus: "Bus", walk: "Walk"],
            value: state.transport,
            style: :inline,
            on_change: {:set, :transport}
          )
        ])
      ])
    ])
  end

  def page(:dates, state) do
    screen("Dates and times", [
      form([
        section("Compact", [
          date_picker("Day", state.day, on_change: {:set, :day}),
          date_picker("Time", state.time, on_change: {:set, :time}),
          date_picker("Both", state.moment, on_change: {:set, :moment})
        ]),
        section("Calendar", [
          date_picker("Day", state.day, style: :graphical, on_change: {:set, :day})
        ]),
        section("Chosen", [text("#{state.day} at #{Time.to_string(state.time)}; #{state.moment}")])
      ])
    ])
  end

  def page(:progress, state) do
    screen("Progress", [
      form([
        section("Linear", [
          progress(value: state.progress, title: "Downloading"),
          progress(title: "Waiting")
        ]),
        section("Circular", [
          hstack([progress(value: state.progress, style: :circular), progress(style: :circular)],
            spacing: 24
          )
        ])
      ])
    ])
  end

  def page(:lists, state) do
    screen("Lists", [
      list([
        section("Fruit", for(fruit <- state.fruits, do: fruit_row(fruit)),
          footer: "#{length(state.fruits)} fruits; tap one to remove it"
        ),
        section(nil, [button("Bring them all back", on_tap: :restore)])
      ])
    ])
  end

  def page(:layout, state) do
    screen("Layout", [
      scroll([
        vstack(
          [
            card([
              text("A card", modifiers: [font: :headline]),
              text("Grouped content on its own surface.")
            ]),
            hstack([text("Leading"), spacer(), text("Trailing")]),
            divider(),
            zstack([
              text("Behind", modifiers: [font: :large_title, opacity: 0.2]),
              text("In front", modifiers: [bold: true])
            ]),
            text("Two columns", modifiers: [font: :headline]),
            grid(for(n <- 1..6, do: card([text("Tile #{n}")], id: n)), columns: 2),
            text("As many as fit", modifiers: [font: :headline]),
            grid(for(n <- 1..8, do: card([icon(:star), text("#{n}")], id: n)), min_width: 90),
            disclosure(
              "More",
              [text("Hidden until opened."), text("Opened and closed by the app's state.")],
              expanded: state.expanded,
              on_toggle: {:set, :expanded}
            ),
            scroll(
              for(
                n <- 1..10,
                do: card([text("Item #{n}")], id: n, modifiers: [frame: [width: 120]])
              ),
              axis: :horizontal
            )
          ],
          spacing: 16,
          alignment: :leading,
          modifiers: [padding: 16]
        )
      ])
    ])
  end

  def page(:presentation, state) do
    screen(
      "Sheets and alerts",
      [
        list([
          section("Show", [
            button("A sheet", on_tap: {:show, :sheet}),
            button("An alert", on_tap: {:show, :alert}),
            button("An action sheet", on_tap: {:show, :confirm})
          ]),
          section(
            "Search the toolbar's list",
            for(fruit <- filtered(state), do: text(fruit, id: fruit))
          ),
          section("Last event", [text(state.last)])
        ]),
        toolbar([
          button("Favourite",
            icon: if(state.favourite, do: :favorite, else: :favorite_border),
            on_tap: :favourite
          ),
          menu("More", [button("Share", icon: :share, on_tap: {:pressed, "share"})], icon: :more)
        ]),
        sheet(
          [
            text("A sheet slides up over the screen."),
            button("Close", style: :prominent, on_tap: {:hide, :sheet})
          ],
          shown: state.sheet,
          title: "Sheet",
          on_dismiss: {:hide, :sheet}
        ),
        alert(
          "Delete the draft?",
          [
            button("Delete", role: :destructive, on_tap: {:pressed, "delete"}),
            button("Cancel", role: :cancel, on_tap: {:hide, :alert})
          ],
          shown: state.alert,
          message: "This cannot be undone.",
          on_dismiss: {:hide, :alert}
        ),
        confirm(
          "Share the photo",
          [
            button("Messages", on_tap: {:pressed, "messages"}),
            button("Mail", on_tap: {:pressed, "mail"}),
            button("Cancel", role: :cancel, on_tap: {:hide, :confirm})
          ],
          shown: state.confirm,
          on_dismiss: {:hide, :confirm}
        )
      ],
      search: state.query,
      on_search: {:set, :query},
      search_prompt: "Fruit"
    )
  end

  def page(:images, _state) do
    screen("Images", [
      scroll([
        vstack(
          [
            text("From the app", modifiers: [font: :headline]),
            image(Application.app_dir(:catalog, "priv/images/title_art.png"),
              modifiers: [corner_radius: 12]
            ),
            text("From the web", modifiers: [font: :headline]),
            image("https://picsum.photos/id/1025/600/400",
              fit: :fill,
              modifiers: [frame: [height: 200, max_width: :infinity], corner_radius: 12]
            )
          ],
          spacing: 12,
          alignment: :leading,
          modifiers: [padding: 16]
        )
      ])
    ])
  end

  def page(:media, state) do
    screen("Media and device", [
      list([
        section(
          "Haptics",
          [
            hstack(
              for(style <- [:selection, :light, :medium, :heavy]) do
                chip("#{style}", id: style, on_tap: {:haptic, style})
              end
            ),
            hstack(
              for(style <- [:success, :warning, :error]) do
                chip("#{style}", id: style, on_tap: {:haptic, style})
              end
            )
          ]
        ),
        section(
          "Photos, camera and files",
          [
            button("Pick up to three photos", icon: :star, on_tap: {:device, :pick_photos}),
            button("Take a photo", icon: :add_circle, on_tap: {:device, :take_photo}),
            button("Record a video", icon: :play, on_tap: {:device, :record_video}),
            button("Pick a file", icon: :list, on_tap: {:device, :pick_files})
          ] ++ picked(state.picked)
        ),
        section("Microphone", [
          button(if(state.recording, do: "Stop recording", else: "Record sound"),
            icon: if(state.recording, do: :close, else: :notifications),
            on_tap: :record
          ),
          button("Play the recording",
            icon: :play,
            disabled: state.recorded == nil,
            on_tap: {:play, :recording}
          )
        ]),
        section(
          "Audio in the background",
          [
            button("Play a song", icon: :play, on_tap: {:play, :song}),
            hstack([
              chip("Pause", id: :pause, on_tap: {:playback, :pause}),
              chip("Resume", id: :resume, on_tap: {:playback, :resume}),
              chip("Stop", id: :stop, on_tap: {:playback, :stop})
            ])
          ],
          footer: "Keeps playing with the screen locked, with the lock screen's controls"
        ),
        section("Video", [
          video(@video, id: :video, on_end: {:pressed, "the video's end"})
        ]),
        section(
          "Camera",
          [
            toggle("Show the camera", value: state.camera, on_change: :camera),
            picker("Facing", [back: "Back", front: "Front"],
              value: state.facing,
              style: :segmented,
              on_change: {:set, :facing}
            )
          ] ++ if(state.camera, do: [camera_preview(facing: state.facing)], else: [])
        ),
        section(
          "Permissions",
          for(name <- [:camera, :microphone, :photos, :location, :notifications]) do
            button("Ask for #{name}", id: name, icon: :lock, on_tap: {:permission, name})
          end
        ),
        section("Share and open", [
          button("Share a line of text", icon: :share, on_tap: {:share, :text}),
          button("Share the last photo",
            icon: :share,
            disabled: state.picked == [],
            on_tap: {:share, :photo}
          ),
          button("Open elixir-lang.org", icon: :send, on_tap: :open_url)
        ]),
        section("Last answer", [text(state.answer, modifiers: [foreground: :secondary])])
      ])
    ])
  end

  def page(:places, state) do
    screen("Location and maps", [
      list([
        section("Where the phone is", [
          button("Find me", icon: :location, on_tap: :locate),
          toggle("Follow me", value: state.following, on_change: :follow),
          text(reading_text(state.reading), modifiers: [foreground: :secondary])
        ]),
        section(
          "Map",
          [
            picker("Style", [standard: "Standard", satellite: "Satellite", hybrid: "Hybrid"],
              value: state.map_style,
              style: :segmented,
              on_change: {:set, :map_style}
            ),
            map(
              center: map_center(state.reading),
              distance: 6000,
              style: state.map_style,
              user_location: state.reading != nil,
              markers: map_markers(state.reading),
              on_select: :place,
              on_move: :moved
            )
          ],
          footer: state.map_note
        )
      ])
    ])
  end

  def page(:fold, state) do
    screen("Folding", [
      list([
        section("The fold", [text(fold_text(state.posture))],
          footer: "Fold the iPhone Duo or an Android foldable, or change its posture in the simulator"
        ),
        section("Hinge", [text(hinge_text(state.posture), modifiers: [foreground: :secondary])])
      ])
    ])
  end

  def page(:notifications, state) do
    screen("Notifications", [
      list([
        section(
          "The app's own",
          [
            button("Show one now", icon: :notifications, on_tap: {:notify, 0}),
            button("Show one in 10 seconds", icon: :refresh, on_tap: {:notify, 10}),
            button("Take back the last",
              icon: :delete,
              disabled: state.notified == 0,
              on_tap: :cancel_notification
            )
          ],
          footer: "Leave the app or lock the phone to see the later one arrive"
        ),
        section(
          "Push",
          [button("Register for push", icon: :send, on_tap: :push)],
          footer: "Needs :push in the app's config, with Apple's push service or Firebase"
        ),
        section("Last answer", [text(state.answer, modifiers: [foreground: :secondary])])
      ])
    ])
  end

  def page(:charts, _state) do
    week = ~w(Mon Tue Wed Thu Fri Sat Sun)
    days = Date.range(~D[2026-10-12], ~D[2026-10-22])

    screen("Charts", [
      list([
        section("Bars", [
          chart(
            [
              series("Coffee", Enum.zip(week, [3, 4, 2, 5, 3, 1, 1])),
              series("Tea", Enum.zip(week, [1, 1, 2, 1, 2, 3, 2]))
            ],
            y_label: "Cups"
          )
        ]),
        section("Lines over days", [
          chart(
            [
              series(
                "Steps",
                Enum.zip(days, [
                  6200,
                  8100,
                  7400,
                  9900,
                  5300,
                  11_200,
                  8700,
                  7600,
                  9100,
                  10_400,
                  6900
                ]), mark: :line),
              series("Goal", Enum.map(days, &{&1, 8000}), mark: :line, colour: "#8E8E93")
            ],
            y_label: "Steps"
          )
        ]),
        section("Area", [
          chart([series("Rain", Enum.zip(0..23, rain()), mark: :area)],
            x_label: "Hour",
            y_label: "mm"
          )
        ]),
        section("Points", [
          chart(
            [
              series("Runs", [{3.0, 17}, {5.0, 27}, {5.0, 25}, {8.0, 44}, {10.0, 52}, {12.0, 66}],
                mark: :point
              )
            ],
            x_label: "km",
            y_label: "Minutes"
          )
        ]),
        section("Pie", [
          chart(
            [
              series("Spending", [{"Rent", 40}, {"Food", 25}, {"Travel", 15}, {"Other", 20}],
                mark: :sector
              )
            ],
            legend: true
          )
        ]),
        section("Donut", [
          chart(
            [
              series("Time", [{"Work", 8}, {"Sleep", 8}, {"Play", 5}, {"Chores", 3}],
                mark: :sector
              )
            ],
            legend: true,
            donut: true
          )
        ])
      ])
    ])
  end

  def page(:custom, state) do
    screen("A view of the app's own", [
      form([
        section("Meter", [native(:meter, value: state.meter, label: "Meter")],
          footer: "Drawn by Swift on iOS and Kotlin on Android, in native/"
        ),
        section(nil, [slider(value: state.meter, on_change: {:set, :meter})])
      ])
    ])
  end

  @doc "The gallery tab: a grid of pictures from the web."
  @spec gallery(map()) :: CauldronNative.UI.Node.t()
  def gallery(_state) do
    screen("Gallery", [
      scroll([
        grid(
          for(n <- [10, 20, 28, 37, 48, 57, 64, 76, 84, 96]) do
            image("https://picsum.photos/id/#{n}/300/300",
              id: n,
              fit: :fill,
              modifiers: [frame: [height: 150, max_width: :infinity], corner_radius: 8]
            )
          end,
          min_width: 150,
          modifiers: [padding: 16]
        )
      ])
    ])
  end

  @doc "The settings, shown in a sheet from the catalog's toolbar."
  @spec settings(map()) :: CauldronNative.UI.Node.t()
  def settings(state) do
    form([
      section("Account", [label("jarius", icon: :account), label("Signed in", icon: :lock)]),
      section("Notifications", [toggle("Wi-Fi", value: state.wifi, on_change: {:set, :wifi})]),
      section("About", [
        text("Catalog 0.1.0"),
        link("Source", "https://github.com/jaman/cauldron")
      ])
    ])
  end

  defp picked([]), do: []

  defp picked(paths) do
    for path <- paths do
      if Path.extname(path) in ~w(.mov .mp4 .m4v),
        do: video(path, id: path),
        else: image(path, id: path, modifiers: [corner_radius: 8, frame: [max_height: 240]])
    end
  end

  defp rain,
    do: [
      0,
      0,
      0,
      0,
      0.2,
      0.6,
      1.4,
      2.1,
      1.8,
      0.9,
      0.4,
      0.2,
      0,
      0,
      0.3,
      1.1,
      2.6,
      3.2,
      2.4,
      1.2,
      0.5,
      0.1,
      0,
      0
    ]

  defp reading_text(nil), do: "Not found yet"

  defp reading_text(reading),
    do:
      "#{Float.round(reading.latitude, 5)}, #{Float.round(reading.longitude, 5)}, within #{round(reading.accuracy)} m"

  defp map_center(nil), do: {48.8606, 2.3200}
  defp map_center(reading), do: {reading.latitude, reading.longitude}

  defp map_markers(reading) do
    places = for {id, title, place} <- @places, do: marker(id, title, place)

    if reading,
      do: [marker(:you, "You", {reading.latitude, reading.longitude}, colour: "#007AFF") | places],
      else: places
  end

  defp fruit_row(fruit), do: button(fruit, id: fruit, icon: :delete, on_tap: {:remove, fruit})

  defp filtered(%{query: ""} = state), do: state.fruits

  defp filtered(state),
    do:
      Enum.filter(
        state.fruits,
        &String.contains?(String.downcase(&1), String.downcase(state.query))
      )

  defp submitted(nil), do: "Press return in the last field"
  defp submitted(text), do: "Submitted: #{text}"

  defp fold_text(nil), do: "This device does not fold"
  defp fold_text(%{fold: fold, angle: nil}), do: fold_name(fold)
  defp fold_text(%{fold: fold, angle: angle}), do: "#{fold_name(fold)}, hinge at #{round(angle)}°"

  defp fold_name(:closed), do: "Closed"
  defp fold_name(:half_open), do: "Half open"
  defp fold_name(:open), do: "Open"
  defp fold_name(:unknown), do: "Not known"

  defp hinge_text(%{hinge: %{} = hinge}) do
    direction = if hinge.vertical, do: "top to bottom", else: "side to side"
    split = if hinge.separating, do: "splits the window in two", else: "does not split the window"
    "Runs #{direction} at #{hinge.x}, #{hinge.y}, #{hinge.width} × #{hinge.height} pixels; #{split}"
  end

  defp hinge_text(_posture), do: "The platform gives no hinge position"
end
